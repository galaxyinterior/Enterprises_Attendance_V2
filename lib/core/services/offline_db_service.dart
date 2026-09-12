import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../../models/attendance_model.dart';

class OfflineDbService {
  static final OfflineDbService _instance = OfflineDbService._internal();
  factory OfflineDbService() => _instance;
  OfflineDbService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance_offline.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        // Attendance offline queue table
        await db.execute('''
          CREATE TABLE offline_attendance (
            attendanceId TEXT PRIMARY KEY,
            businessId TEXT,
            employeeId TEXT,
            employeeName TEXT,
            date TEXT,
            shiftId TEXT,
            checkInTime TEXT,
            checkOutTime TEXT,
            status TEXT,
            lateReason TEXT,
            lateMinutes INTEGER,
            approvalStatus TEXT,
            confidence REAL,
            syncStatus TEXT,
            createdAt TEXT,
            updatedAt TEXT
          )
        ''');

        // Cached local employee embeddings table
        await db.execute('''
          CREATE TABLE local_employees (
            employeeId TEXT PRIMARY KEY,
            businessId TEXT,
            empCode TEXT,
            fullName TEXT,
            phone TEXT,
            department TEXT,
            designation TEXT,
            assignedShiftId TEXT,
            faceEmbedding TEXT
          )
        ''');

        // Cached local custom shifts table
        await db.execute('''
          CREATE TABLE local_shifts (
            shiftId TEXT PRIMARY KEY,
            businessId TEXT,
            shopId TEXT,
            shiftName TEXT,
            startTime TEXT,
            endTime TEXT,
            maxCheckInTime TEXT,
            gracePeriodMinutes INTEGER,
            createdAt TEXT
          )
        ''');

        // Indexes for high performance
        await db.execute('CREATE INDEX IF NOT EXISTS idx_emp_business ON local_employees(businessId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_att_sync ON offline_attendance(syncStatus)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_att_dup ON offline_attendance(employeeId, date)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE local_employees ADD COLUMN empCode TEXT');
            await db.execute('ALTER TABLE local_employees ADD COLUMN phone TEXT');
            await db.execute('ALTER TABLE local_employees ADD COLUMN department TEXT');
            await db.execute('ALTER TABLE local_employees ADD COLUMN designation TEXT');
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE offline_attendance ADD COLUMN lateReason TEXT');
            await db.execute('ALTER TABLE offline_attendance ADD COLUMN lateMinutes INTEGER');
            await db.execute('ALTER TABLE offline_attendance ADD COLUMN approvalStatus TEXT');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS local_shifts (
                shiftId TEXT PRIMARY KEY,
                businessId TEXT,
                shopId TEXT,
                shiftName TEXT,
                startTime TEXT,
                endTime TEXT,
                maxCheckInTime TEXT,
                gracePeriodMinutes INTEGER,
                createdAt TEXT
              )
            ''');
          } catch (_) {}
        }
      },
    );
  }

  // Insert or queue offline attendance
  Future<void> insertAttendance(AttendanceModel attendance) async {
    final db = await database;
    await db.insert(
      'offline_attendance',
      attendance.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Check if employee has logged attendance recently (prevents double check-ins within windowMinutes)
  Future<bool> hasRecentAttendance(String employeeId, String date, {int windowMinutes = 5}) async {
    final db = await database;
    final List<Map<String, dynamic>> records = await db.query(
      'offline_attendance',
      where: 'employeeId = ? AND date = ?',
      whereArgs: [employeeId, date],
      orderBy: 'checkInTime DESC',
      limit: 1,
    );

    if (records.isEmpty) return false;

    final lastCheckInStr = records.first['checkInTime'];
    if (lastCheckInStr == null) return false;

    try {
      final lastTime = DateTime.parse(lastCheckInStr);
      final difference = DateTime.now().difference(lastTime);
      return difference.inMinutes < windowMinutes;
    } catch (_) {
      return false;
    }
  }

  /// Clean up local attendance records older than [days] (Default: 7 days / 1 week)
  Future<int> deleteAttendanceOlderThan({int days = 7}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final cutoffStr = cutoff.toIso8601String();
    return await db.delete(
      'offline_attendance',
      where: 'createdAt < ?',
      whereArgs: [cutoffStr],
    );
  }

  /// Retrieves today's attendance record for an employee from local SQLite
  Future<Map<String, dynamic>?> getTodayAttendanceRecord(String employeeId, String date) async {
    final db = await database;
    final List<Map<String, dynamic>> records = await db.query(
      'offline_attendance',
      where: 'employeeId = ? AND date = ?',
      whereArgs: [employeeId, date],
      orderBy: 'checkInTime DESC',
      limit: 1,
    );
    if (records.isNotEmpty) {
      return records.first;
    }
    return null;
  }

  // Get all pending unsynced attendance records (including RETRY & FAILED)
  Future<List<AttendanceModel>> getPendingAttendance() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'offline_attendance',
      where: 'syncStatus IN (?, ?, ?)',
      whereArgs: ['PENDING', 'RETRY', 'FAILED'],
    );
    return maps.map((map) => AttendanceModel.fromMap(map)).toList();
  }

  // Mark attendance as synced
  Future<void> markAttendanceSynced(String attendanceId) async {
    final db = await database;
    await db.update(
      'offline_attendance',
      {
        'syncStatus': 'SYNCED',
        'serverAck': 1,
        'lastError': null,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'attendanceId = ?',
      whereArgs: [attendanceId],
    );
  }

  // Record a sync attempt failure or retry state
  Future<void> recordSyncAttempt({
    required String attendanceId,
    required String status, // SYNCING / RETRY / FAILED
    required int retryCount,
    String? errorMsg,
  }) async {
    final db = await database;
    await db.update(
      'offline_attendance',
      {
        'syncStatus': status,
        'retryCount': retryCount,
        'lastError': errorMsg,
        'lastAttempt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'attendanceId = ?',
      whereArgs: [attendanceId],
    );
  }

  // Save/Sync list of employees into local SQLite database
  Future<void> saveLocalEmployees(List<Map<String, dynamic>> employeeMaps) async {
    final db = await database;
    final batch = db.batch();
    for (var emp in employeeMaps) {
      final String empId = emp['employeeId'] ?? '';
      if (empId.isEmpty) continue;
      final embedding = emp['faceEmbedding'];
      batch.insert(
        'local_employees',
        {
          'employeeId': empId,
          'businessId': emp['businessId'] ?? '',
          'empCode': emp['employeeCode'] ?? emp['empCode'] ?? '',
          'fullName': emp['fullName'] ?? '',
          'phone': emp['phone'] ?? emp['phoneNumber'] ?? '',
          'department': emp['department'] ?? '',
          'designation': emp['designation'] ?? '',
          'assignedShiftId': emp['assignedShiftId'] ?? '',
          'faceEmbedding': embedding != null ? jsonEncode(embedding) : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Get all cached local employees for 100% offline face recognition
  Future<List<Map<String, dynamic>>> getLocalEmployeesWithEmbeddings(String businessId) async {
    final db = await database;
    List<Map<String, dynamic>> rows = [];
    if (businessId.isNotEmpty) {
      rows = await db.query(
        'local_employees',
        where: 'businessId = ?',
        whereArgs: [businessId],
      );
    }
    // Fallback: If no records found for specified businessId, fetch all local employees
    if (rows.isEmpty) {
      rows = await db.query('local_employees');
    }

    List<Map<String, dynamic>> result = [];
    for (var row in rows) {
      final embeddingStr = row['faceEmbedding'];
      if (embeddingStr != null && embeddingStr.toString().isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(embeddingStr);
          final List<double> vector = decoded.map((e) => (e as num).toDouble()).toList();
          if (vector.isNotEmpty) {
            result.add({
              'employeeId': row['employeeId'],
              'businessId': row['businessId'],
              'empCode': row['empCode'],
              'employeeCode': row['empCode'],
              'fullName': row['fullName'],
              'phone': row['phone'],
              'phoneNumber': row['phone'],
              'department': row['department'],
              'designation': row['designation'],
              'assignedShiftId': row['assignedShiftId'],
              'faceEmbedding': vector,
            });
          }
        } catch (_) {}
      }
    }
    return result;
  }

  // Get all local employees across all business tenants or specified tenant
  Future<List<Map<String, dynamic>>> getLocalEmployees([String businessId = '']) async {
    if (businessId.isEmpty) {
      final db = await database;
      final rows = await db.query('local_employees');
      List<Map<String, dynamic>> result = [];
      for (var row in rows) {
        final embeddingStr = row['faceEmbedding'];
        List<double> vector = [];
        if (embeddingStr != null && embeddingStr.toString().isNotEmpty) {
          try {
            final List<dynamic> decoded = jsonDecode(embeddingStr as String);
            vector = decoded.map((e) => (e as num).toDouble()).toList();
          } catch (_) {}
        }
        result.add({
          'employeeId': row['employeeId'],
          'businessId': row['businessId'],
          'fullName': row['fullName'],
          'faceEmbedding': vector,
        });
      }
      return result;
    }
    return getLocalEmployeesWithEmbeddings(businessId);
  }

  // Save/Cache shifts locally in SQLite
  Future<void> saveLocalShifts(List<Map<String, dynamic>> shiftMaps) async {
    final db = await database;
    final batch = db.batch();
    for (var shift in shiftMaps) {
      final String id = shift['shiftId'] ?? '';
      if (id.isEmpty) continue;
      batch.insert(
        'local_shifts',
        {
          'shiftId': id,
          'businessId': shift['businessId'] ?? '',
          'shopId': shift['shopId'] ?? '',
          'shiftName': shift['shiftName'] ?? '',
          'startTime': shift['startTime'] ?? '09:00 AM',
          'endTime': shift['endTime'] ?? '06:00 PM',
          'maxCheckInTime': shift['maxCheckInTime'] ?? '09:15 AM',
          'gracePeriodMinutes': shift['gracePeriodMinutes'] ?? 15,
          'createdAt': shift['createdAt'] is DateTime
              ? (shift['createdAt'] as DateTime).toIso8601String()
              : (shift['createdAt']?.toString() ?? DateTime.now().toIso8601String()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Get all cached local shifts for offline kiosk & admin validation
  Future<List<Map<String, dynamic>>> getLocalShifts(String businessId) async {
    final db = await database;
    return await db.query(
      'local_shifts',
      where: 'businessId = ?',
      whereArgs: [businessId],
    );
  }

  // Update late attendance approval status locally
  Future<void> updateAttendanceApproval(String attendanceId, String approvalStatus, String status) async {
    final db = await database;
    await db.update(
      'offline_attendance',
      {
        'approvalStatus': approvalStatus,
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'attendanceId = ?',
      whereArgs: [attendanceId],
    );
  }
}
