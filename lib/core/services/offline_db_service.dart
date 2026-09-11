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
      version: 2,
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

  // Get all pending unsynced attendance records
  Future<List<AttendanceModel>> getPendingAttendance() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'offline_attendance',
      where: 'syncStatus = ?',
      whereArgs: ['PENDING'],
    );
    return maps.map((map) => AttendanceModel.fromMap(map)).toList();
  }

  // Mark attendance as synced
  Future<void> markAttendanceSynced(String attendanceId) async {
    final db = await database;
    await db.update(
      'offline_attendance',
      {'syncStatus': 'COMPLETED'},
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
    final List<Map<String, dynamic>> rows = await db.query(
      'local_employees',
      where: 'businessId = ?',
      whereArgs: [businessId],
    );

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
}
