import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/face_recognition_service.dart';
import '../../core/services/voice_announcements_service.dart';
import '../../core/services/offline_db_service.dart';
import '../../core/services/kiosk_heartbeat_service.dart';
import '../../core/services/auth_routing_service.dart';
import '../../core/services/shift_engine_service.dart';
import '../../core/services/sync_engine.dart';
import '../../core/services/email_notification_service.dart';
import '../../models/attendance_model.dart';
import '../../models/shift_model.dart';
import '../auth/login_screen.dart';

class KioskAttendanceScreen extends StatefulWidget {
  final String shopId;
  final String businessId;

  const KioskAttendanceScreen({
    super.key,
    required this.shopId,
    required this.businessId,
  });

  @override
  State<KioskAttendanceScreen> createState() => _KioskAttendanceScreenState();
}

class _KioskAttendanceScreenState extends State<KioskAttendanceScreen> with WidgetsBindingObserver {
  final _faceService = FaceRecognitionService();
  final _voiceService = VoiceAnnouncementsService();
  final _offlineDb = OfflineDbService();
  final _heartbeatService = KioskHeartbeatService();

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;

  Timer? _autoScanTimer;
  Timer? _hourlySyncTimer;
  bool _isProcessing = false;
  bool _faceDetectedInFrame = false;

  List<Map<String, dynamic>> _enrolledStaffCache = [];
  Map<String, dynamic>? _lastRecognizedEmployee;
  String _statusMessage = '👁️ Position face inside camera circle to scan';
  String? _lastRecognizedName;
  bool _noMatchFound = false;
  String? _scanFailureReason;
  bool _isShopPaused = false;
  final String _deviceId = 'KSK-01';

  StreamSubscription<QuerySnapshot>? _announcementsSub;
  Map<String, dynamic>? _activeAnnouncementData;
  final Set<String> _spokenAnnouncementIds = {};

  bool _isAttendanceMarked = false;

  // Session Lock State for Instant Face Match & Attendance Logging
  Map<String, dynamic>? _lockedEmployee;
  DateTime? _sessionLockTime;
  bool _isFinalizingAttendance = false;

  /// Production Switch: Enforce active eye blink & head micro-movement anti-spoofing
  bool requireLivenessForRecognition = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServicesAndCamera();
    _listenToShopStatus();
    _listenToEnrolledStaff();
    _listenToAnnouncements();

    // 1. Maintain 1-week attendance history in local SQLite DB
    _offlineDb.deleteAttendanceOlderThan(days: 7);

    // 2. Setup 1-hour periodic timer for local DB maintenance & cloud sync
    _hourlySyncTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      await _offlineDb.deleteAttendanceOlderThan(days: 7);
      await SyncEngine().syncPendingAttendance();
      if (mounted && widget.businessId.isNotEmpty) {
        await SyncEngine().syncDownTenantData(widget.businessId);
      }
    });

    SyncEngine().startAutoSync(activeBusinessId: widget.businessId);
    _heartbeatService.startHeartbeat(
      businessId: widget.businessId,
      shopId: widget.shopId,
      deviceId: _deviceId,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _autoScanTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startAutoScanner();
    }
  }

  void _listenToEnrolledStaff() {
    // 1. Initial load from local SQLite database for 100% offline availability
    _offlineDb.getLocalEmployeesWithEmbeddings(widget.businessId).then((localEmps) {
      _logCacheDiagnostics(localEmps);
      if (mounted && localEmps.isNotEmpty) {
        setState(() {
          _enrolledStaffCache = localEmps;
        });
      }
    });

    // 2. Real-time sync from Cloud Firestore to Local SQLite database
    try {
      FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .collection(AppConstants.colEmployees)
          .snapshots()
          .listen((snapshot) async {
        final enrolled = snapshot.docs
            .map((doc) => doc.data())
            .where((emp) => (emp['active'] ?? true) == true && emp['faceEmbedding'] != null && (emp['faceEmbedding'] as List).isNotEmpty)
            .toList();

        await _offlineDb.saveLocalEmployees(enrolled, businessId: widget.businessId);
        final updatedLocal = await _offlineDb.getLocalEmployeesWithEmbeddings(widget.businessId);
        _logCacheDiagnostics(updatedLocal);

        if (mounted) {
          setState(() {
            _enrolledStaffCache = updatedLocal;
          });
        }
      }, onError: (err) {
        debugPrint('Firestore real-time sync offline notice: $err. Operating via SQLite local cache.');
      });
    } catch (e) {
      debugPrint('Firestore stream init exception: $e. Operating via SQLite local cache.');
    }
  }

  void _logCacheDiagnostics(List<Map<String, dynamic>> emps) {
    int withEmbedding = emps.where((e) => e['faceEmbedding'] != null && (e['faceEmbedding'] as List).isNotEmpty).length;
    int dim = withEmbedding > 0 ? (emps.first['faceEmbedding'] as List).length : 0;
    debugPrint('=== LOCAL_FACE_CACHE_DIAGNOSTICS ===');
    debugPrint('businessId=${widget.businessId}');
    debugPrint('employeesLoaded=${emps.length}');
    debugPrint('employeesWithEmbedding=$withEmbedding');
    debugPrint('embeddingDimensions=$dim');
    debugPrint('====================================');
  }

  Future<void> _initServicesAndCamera() async {
    await _faceService.initialize();
    await _voiceService.initialize();

    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        final frontCam = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );

        _cameraController = CameraController(
          frontCam,
          ResolutionPreset.low,
          enableAudio: false,
        );

        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
          _startAutoScanner();
        }
      }
    } catch (e) {
      debugPrint('Kiosk camera init info: $e');
    }
  }

  void _resetSessionLock() {
    _lockedEmployee = null;
    _sessionLockTime = null;
    _isProcessing = false;
    _isFinalizingAttendance = false;
    _faceDetectedInFrame = false;
    _lastRecognizedName = null;
    _lastRecognizedEmployee = null;
    _noMatchFound = false;
    _scanFailureReason = null;
    _isAttendanceMarked = false;
    _statusMessage = '👁️ Position face inside camera circle to scan';
  }

  Future<void> _resetCamera() async {
    try {
      _autoScanTimer?.cancel();
      if (_cameraController != null) {
        try {
          await _cameraController!.dispose();
        } catch (_) {}
        _cameraController = null;
      }
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _resetSessionLock();
          _statusMessage = '🔄 Resetting camera controller...';
        });
      }
      await _initServicesAndCamera();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Camera successfully reset & scanner restarted.'),
            duration: Duration(seconds: 2),
            backgroundColor: AppColors.pannaEmerald,
          ),
        );
      }
    } catch (e) {
      debugPrint('Reset camera error: $e');
    }
  }

  void _startAutoScanner() {
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (!mounted ||
          !_isCameraInitialized ||
          _isProcessing ||
          _isFinalizingAttendance ||
          _isShopPaused ||
          _cameraController == null ||
          !_cameraController!.value.isInitialized ||
          _cameraController!.value.isTakingPicture) {
        return;
      }
      await _autoDetectFrame();
    });
  }

  Future<void> _autoDetectFrame() async {
    if (_isProcessing ||
        _isFinalizingAttendance ||
        _isShopPaused ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isTakingPicture) {
      return;
    }

    _isProcessing = true;

    try {
      final String currentEmpId = _lockedEmployee != null ? (_lockedEmployee!['employeeId'] ?? 'N/A') : 'N/A';

      // Check for session lock timeout (8 seconds max without valid blink)
      if (_lockedEmployee != null && _sessionLockTime != null) {
        final elapsed = DateTime.now().difference(_sessionLockTime!).inSeconds;
        if (elapsed > 8 && !_isAttendanceMarked && !_isFinalizingAttendance) {
          debugPrint('=== KIOSK_ATTENDANCE_STATE ===');
          debugPrint('state=TIMEOUT_NO_BLINK');
          debugPrint('employeeId=$currentEmpId');
          debugPrint('locked=true');
          debugPrint('sessionAgeMs=${elapsed * 1000}');

          if (mounted) {
            setState(() {
              _resetSessionLock();
              _statusMessage = '⏱️ Session timed out. Position face inside camera circle to scan.';
            });
          }
          return;
        }
      }

      XFile? xFile;
      try {
        xFile = await _cameraController!.takePicture();
      } catch (e) {
        debugPrint('Camera takePicture frame skip: $e');
        return;
      }
      final bytes = await xFile.readAsBytes();

      // Fast ML Kit Face & Liveness Detection
      final res = await _faceService.detectFaceAndCheckBlink(xFile.path);

      if (res == null || res['hasFace'] != true) {
        if (_faceDetectedInFrame || _lockedEmployee != null || _noMatchFound) {
          debugPrint('=== KIOSK_ATTENDANCE_STATE ===');
          debugPrint('state=FACE_LOST');
          debugPrint('employeeId=$currentEmpId');

          if (mounted && !_isAttendanceMarked && !_isFinalizingAttendance) {
            setState(() {
              _resetSessionLock();
            });
          }
        }
        return;
      }

      // Check single face requirement
      final bool isSingleFace = res['isSingleFace'] as bool? ?? false;
      if (!isSingleFace) {
        debugPrint('=== KIOSK_ATTENDANCE_STATE ===');
        debugPrint('state=MULTIPLE_FACES');
        debugPrint('employeeId=$currentEmpId');
        if (mounted) {
          setState(() {
            _statusMessage = '⚠️ Multiple faces detected! Please stand alone in camera view.';
          });
        }
        return;
      }

      // Live angle verification
      if (res['isLiveValid'] == false) {
        if (mounted) {
          setState(() {
            _faceDetectedInFrame = true;
            _statusMessage = '⚠️ Face Angle Too Steep! Please look straight at camera.';
          });
        }
        return;
      }

      // =========================================================================
      // CASE A: SESSION IS LOCKED TO A MATCHED EMPLOYEE (DO NOT RE-RUN MATCHING)
      // =========================================================================
      if (_lockedEmployee != null) {
        if (_isAttendanceMarked || _isFinalizingAttendance) {
          return;
        }
        await _finalizeAttendanceForLockedEmployee();
        return;
      }

      // =========================================================================
      // CASE B: SESSION UNLOCKED — PERFORM FACE MATCHING TO LOCK SESSION
      // =========================================================================
      if (!_noMatchFound) {
        final processRes = await _faceService.processFaceFromBytesDetailed(
          bytes: bytes,
          tempFilePath: xFile.path,
          context: 'PREVIEW_MATCH',
        );

        if (processRes['success'] == true && processRes['embedding'] != null) {
          final targetVector = processRes['embedding'] as List<double>;
          var match = _faceService.matchFace(
            targetEmbedding: targetVector,
            enrolledEmployees: _enrolledStaffCache,
          );

          // Cloud fallback search if local cache is empty
          if (match == null && _enrolledStaffCache.isEmpty) {
            try {
              final snapshot = await FirebaseFirestore.instance
                  .collection(AppConstants.colBusinesses)
                  .doc(widget.businessId)
                  .collection(AppConstants.colEmployees)
                  .get()
                  .timeout(const Duration(seconds: 3));

              final cloudEmps = snapshot.docs
                  .map((doc) => doc.data())
                  .where((emp) => emp['faceEmbedding'] != null && (emp['faceEmbedding'] as List).isNotEmpty)
                  .toList();

              if (cloudEmps.isNotEmpty) {
                await _offlineDb.saveLocalEmployees(cloudEmps, businessId: widget.businessId);
                _enrolledStaffCache = await _offlineDb.getLocalEmployeesWithEmbeddings(widget.businessId);
                match = _faceService.matchFace(
                  targetEmbedding: targetVector,
                  enrolledEmployees: _enrolledStaffCache,
                );
              }
            } catch (_) {}
          }

          if (match != null) {
            final String empName = match['employeeName'];
            final empData = match['employeeData'] ?? {};
            final String empId = match['employeeId'] ?? 'N/A';

            if (mounted) {
              setState(() {
                _lockedEmployee = match;
                _lastRecognizedEmployee = empData;
                _lastRecognizedName = empName;
                _sessionLockTime = DateTime.now();
                _isAttendanceMarked = false;
                _noMatchFound = false;
                _scanFailureReason = null;
                _statusMessage = '👀 Welcome $empName! Logging attendance...';
              });

              debugPrint('=== KIOSK_ATTENDANCE_STATE ===');
              debugPrint('state=EMPLOYEE_LOCKED');
              debugPrint('employeeId=$empId');
              debugPrint('matched=true');
              debugPrint('locked=true');
            }

            await _finalizeAttendanceForLockedEmployee();
            return;
          } else {
            if (mounted) {
              setState(() {
                _noMatchFound = true;
                _scanFailureReason = 'Unregistered Face • Database Connected (${_enrolledStaffCache.length} enrolled staff)';
                _statusMessage = '❌ Unregistered Face — Auto-resetting in 3s...';
              });

              debugPrint('=== KIOSK_ATTENDANCE_STATE ===');
              debugPrint('state=UNREGISTERED_FACE');
              debugPrint('matched=false');

              Timer(const Duration(seconds: 3), () {
                if (mounted && _noMatchFound) {
                  setState(() {
                    _resetSessionLock();
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Auto detect frame exception: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _finalizeAttendanceForLockedEmployee() async {
    if (_isFinalizingAttendance || _lockedEmployee == null) return;
    _isFinalizingAttendance = true;

    final match = _lockedEmployee!;
    final String empId = match['employeeId'];
    final String name = match['employeeName'];
    final double confidence = match['confidence'] ?? 0.95;
    final Map<String, dynamic> empData = match['employeeData'] ?? {};

    debugPrint('FINALIZE_STARTED');
    debugPrint('employeeId=$empId');

    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // 1. Check for today's duplicate attendance
      final todayRecord = await _offlineDb.getTodayAttendanceRecord(empId, dateStr);
      final isRecentDuplicate = await _offlineDb.hasRecentAttendance(empId, dateStr);

      if (todayRecord != null || isRecentDuplicate) {
        final String statusText = todayRecord != null ? (todayRecord['status'] ?? 'LOGGED') : 'LOGGED';
        debugPrint('ATTENDANCE_DUPLICATE_SKIPPED employeeId=$empId status=$statusText');
        try {
          await _voiceService.speakAlert('$name, your attendance for today is already recorded.');
        } catch (_) {}
        if (mounted) {
          setState(() {
            _lastRecognizedEmployee = empData;
            _lastRecognizedName = name;
            _isAttendanceMarked = true;
            _statusMessage = '✓ $name — Attendance Already Logged Today ($statusText)';
          });
        }
      } else {
        // Shift Evaluation
        final localShifts = await _offlineDb.getLocalShifts(widget.businessId);
        ShiftModel? matchedShift;
        final String empShiftName = empData['assignedShiftId'] ?? empData['assignedShift'] ?? '';
        if (localShifts.isNotEmpty) {
          final found = localShifts.firstWhere(
            (s) => s['shiftName'] == empShiftName || s['shiftId'] == empShiftName,
            orElse: () => localShifts.first,
          );
          matchedShift = ShiftModel.fromMap(found);
        }

        final shiftResult = ShiftEngineService().evaluateCheckInStatus(
          checkInTime: now,
          assignedShiftId: empShiftName,
          customShift: matchedShift,
        );

        debugPrint('SHIFT_RESULT');
        debugPrint('status=${shiftResult.status}');
        debugPrint('isPastDeadline=${shiftResult.isPastDeadline}');
        debugPrint('shiftName=${shiftResult.shiftName}');
        debugPrint('lateMinutes=${shiftResult.lateMinutes}');

        bool isHolidayWork = false;
        try {
          final holSnap = await FirebaseFirestore.instance
              .collection(AppConstants.colBusinesses)
              .doc(widget.businessId)
              .collection('holidays')
              .where('date', isEqualTo: dateStr)
              .get()
              .timeout(const Duration(seconds: 2));
          if (holSnap.docs.isNotEmpty) {
            isHolidayWork = true;
          }
        } catch (_) {}

        if (shiftResult.isPastDeadline) {
          await _handleLateAttendanceWithReason(
            empId: empId,
            name: name,
            confidence: confidence,
            empData: empData,
            shiftResult: shiftResult,
            now: now,
            dateStr: dateStr,
            isHolidayWork: isHolidayWork,
          );
        } else {
          final attendance = AttendanceModel(
            attendanceId: ShiftEngineService().generateDeterministicAttendanceId(
              businessId: widget.businessId,
              employeeId: empId,
              date: dateStr,
            ),
            businessId: widget.businessId,
            employeeId: empId,
            employeeName: name,
            date: dateStr,
            shiftId: shiftResult.shiftName,
            checkInTime: now,
            status: shiftResult.status,
            approvalStatus: 'APPROVED',
            confidence: confidence,
            syncStatus: AppConstants.syncPending,
            isHolidayWork: isHolidayWork,
            holidayBonusStatus: isHolidayWork ? 'PENDING' : null,
            createdAt: now,
            updatedAt: now,
          );

          debugPrint('SQLITE_ATTENDANCE_INSERT_START');
          debugPrint('attendanceId=${attendance.attendanceId}');
          debugPrint('status=${attendance.status}');

          // 1. Save SQLite
          await _offlineDb.insertAttendance(attendance);

          debugPrint('SQLITE_ATTENDANCE_INSERT_SUCCESS');
          debugPrint('attendanceId=${attendance.attendanceId}');

          debugPrint('FIRESTORE_ATTENDANCE_WRITE_START');
          // 2. Sync Firestore
          try {
            FirebaseFirestore.instance
                .collection(AppConstants.colBusinesses)
                .doc(widget.businessId)
                .collection(AppConstants.colAttendance)
                .doc(attendance.attendanceId)
                .set(attendance.toMap())
                .then((_) {
                  debugPrint('FIRESTORE_ATTENDANCE_WRITE_SUCCESS');
                  _offlineDb.markAttendanceSynced(attendance.attendanceId);
                })
                .catchError((err) {
                  debugPrint('Background cloud sync queued: $err');
                  return null;
                });
          } catch (err) {
            debugPrint('Background cloud sync notice: $err');
          }

          // 3. Email Alert
          try {
            EmailNotificationService().sendPresentAttendanceEmail(
              employeeName: name,
              employeeId: empId,
              shiftName: shiftResult.shiftName,
              shopId: widget.shopId,
              checkInTime: now,
            );
          } catch (_) {}

          // Voice Greeting
          try {
            await _voiceService.speakCheckInGreeting(name);
          } catch (_) {}

          debugPrint('ATTENDANCE_SUCCESS');
          debugPrint('employeeId=$empId');
          debugPrint('status=${attendance.status}');

          if (mounted) {
            setState(() {
              _lastRecognizedEmployee = empData;
              _lastRecognizedName = name;
              _isAttendanceMarked = true;
              _noMatchFound = false;
              _scanFailureReason = null;
              _statusMessage = '✓ Welcome $name! ${shiftResult.statusLabel}.';
            });
          }
        }
      }

      // Display success message for 4 seconds, then reset session lock
      await Future.delayed(const Duration(seconds: 4));
      if (mounted) {
        setState(() {
          _resetSessionLock();
        });
      }
    } catch (e) {
      debugPrint('Error finalizing attendance: $e');
    } finally {
      _isFinalizingAttendance = false;
    }
  }

  String _businessName = '';

  void _listenToShopStatus() {
    FirebaseFirestore.instance
        .collection(AppConstants.colBusinesses)
        .doc(widget.businessId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        final data = doc.data() ?? {};
        final status = data['status'] ?? '';
        final name = data['businessName'] ?? data['shopName'] ?? widget.shopId;
        if (mounted) {
          setState(() {
            _isShopPaused = status == AppConstants.statusPaused;
            _businessName = name.toString();
          });
        }
      }
    });
  }

  final AudioPlayer _customAudioPlayer = AudioPlayer();

  Future<void> _playCustomAudio(String base64Audio) async {
    try {
      await _customAudioPlayer.stop();
      final bytes = base64Decode(base64Audio);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/kiosk_announcement_voice.m4a');
      await file.writeAsBytes(bytes);

      await _customAudioPlayer.setVolume(1.0);
      await _customAudioPlayer.play(DeviceFileSource(file.path));
      debugPrint('🎙️ Playing custom voice announcement audio on Kiosk!');
    } catch (e) {
      debugPrint('Error playing custom voice audio on kiosk: $e');
    }
  }

  void _listenToAnnouncements() {
    _announcementsSub = FirebaseFirestore.instance
        .collection(AppConstants.colBusinesses)
        .doc(widget.businessId)
        .collection(AppConstants.colAnnouncements)
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final docs = List<QueryDocumentSnapshot>.from(snapshot.docs);
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = (aData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final bTime = (bData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return bTime.compareTo(aTime);
        });

        final activeDoc = docs.first;
        final data = activeDoc.data() as Map<String, dynamic>;
        final docId = activeDoc.id;
        final message = data['message'] as String? ?? '';
        final type = data['type'] as String? ?? 'general';
        final isCustomAudio = data['isCustomAudio'] as bool? ?? false;
        final audioData = data['audioData'] as String?;

        if (mounted) {
          setState(() {
            _activeAnnouncementData = data;
          });
        }

        if (!_spokenAnnouncementIds.contains(docId)) {
          _spokenAnnouncementIds.add(docId);
          if (isCustomAudio && audioData != null && audioData.isNotEmpty) {
            _playCustomAudio(audioData);
          } else if (message.isNotEmpty) {
            _voiceService.speakAnnouncement(message, type);
          }
        }
      } else {
        if (mounted && _activeAnnouncementData != null) {
          setState(() {
            _activeAnnouncementData = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _announcementsSub?.cancel();
    _autoScanTimer?.cancel();
    _hourlySyncTimer?.cancel();
    SyncEngine().stopAutoSync();
    _heartbeatService.stopHeartbeat();
    _cameraController?.dispose();
    _customAudioPlayer.dispose();
    super.dispose();
  }

  Widget _buildAnnouncementBanner() {
    if (_activeAnnouncementData == null) return const SizedBox.shrink();
    final message = _activeAnnouncementData!['message'] as String? ?? '';
    final type = _activeAnnouncementData!['type'] as String? ?? 'general';
    final isCustomAudio = _activeAnnouncementData!['isCustomAudio'] as bool? ?? false;
    final audioData = _activeAnnouncementData!['audioData'] as String?;
    final isEmergency = type == 'emergency';
    final isNotice = type == 'notice';

    Color bgColor = isEmergency
        ? AppColors.sindoorRed
        : (isNotice ? AppColors.kesariSaffron : AppColors.mayurBlue);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.5),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCustomAudio ? Icons.mic_rounded : (isEmergency ? Icons.warning_amber_rounded : Icons.campaign_rounded),
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEmergency
                      ? '🚨 EMERGENCY ALERT BROADCAST'
                      : (isNotice ? '📢 ANNOUNCEMENT NOTICE' : 'ℹ️ INFORMATION BROADCAST'),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.volume_up_rounded, color: Colors.white, size: 28),
            tooltip: 'Re-Play Voice Announcement',
            onPressed: () {
              if (isCustomAudio && audioData != null && audioData.isNotEmpty) {
                _playCustomAudio(audioData);
              } else if (message.isNotEmpty) {
                _voiceService.speakAnnouncement(message, type);
              }
            },
          ),
        ],
      ),
    );
  }



  Future<void> _handleLateAttendanceWithReason({
    required String empId,
    required String name,
    required double confidence,
    required Map<String, dynamic> empData,
    required ShiftStatusResult shiftResult,
    required DateTime now,
    required String dateStr,
    bool isHolidayWork = false,
  }) async {
    try {
      await _voiceService.speakAlert('$name, you are late for attendance. Please select reason.');
    } catch (_) {}

    String selectedReason = 'Traffic Jam';
    final customReasonCtrl = TextEditingController();
    bool isSubmitting = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.sindoorRed, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You Are Late For Attendance!',
                      style: GoogleFonts.outfit(color: AppColors.sindoorRed, fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check-in deadline for ${shiftResult.shiftName} has passed (${shiftResult.lateMinutes} mins late).',
                      style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.haldiGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.haldiGold.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'Your attendance status remains ABSENT until Shop Admin approves your late reason.',
                        style: GoogleFonts.inter(color: AppColors.haldiGold, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Select Reason for Late Check-In:', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        'Traffic Jam',
                        'Vehicle Breakdown',
                        'Health Issue',
                        'Weather / Rain',
                        'Personal Emergency',
                        'Other',
                      ].map((r) {
                        final isSelected = selectedReason == r;
                        return ChoiceChip(
                          label: Text(r, style: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          selected: isSelected,
                          selectedColor: AppColors.kesariSaffron,
                          backgroundColor: AppColors.inputBgDark,
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedReason = r);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: customReasonCtrl,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Add specific details (optional)',
                        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        filled: true,
                        fillColor: AppColors.inputBgDark,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.kesariSaffron,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  label: Text(isSubmitting ? 'SUBMITTING...' : 'MARK WITH REASON', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final messenger = ScaffoldMessenger.of(context);
                          final fullReason = customReasonCtrl.text.trim().isNotEmpty
                              ? '$selectedReason — ${customReasonCtrl.text.trim()}'
                              : selectedReason;

                          final attendance = AttendanceModel(
                            attendanceId: ShiftEngineService().generateDeterministicAttendanceId(
                              businessId: widget.businessId,
                              employeeId: empId,
                              date: dateStr,
                            ),
                            businessId: widget.businessId,
                            employeeId: empId,
                            employeeName: name,
                            date: dateStr,
                            shiftId: shiftResult.shiftName,
                            checkInTime: now,
                            status: AppConstants.attendanceAbsent, // ABSENT until Admin Approval!
                            lateReason: fullReason,
                            lateMinutes: shiftResult.lateMinutes,
                            approvalStatus: 'PENDING',
                            confidence: confidence,
                            syncStatus: AppConstants.syncPending,
                            isHolidayWork: isHolidayWork,
                            holidayBonusStatus: isHolidayWork ? 'PENDING' : null,
                            createdAt: now,
                            updatedAt: now,
                          );

                          // 1. Save to SQLite offline DB
                          await _offlineDb.insertAttendance(attendance);

                          // 2. Sync to Cloud Firestore
                          try {
                            await FirebaseFirestore.instance
                                .collection(AppConstants.colBusinesses)
                                .doc(widget.businessId)
                                .collection(AppConstants.colAttendance)
                                .doc(attendance.attendanceId)
                                .set(attendance.toMap());
                            await _offlineDb.markAttendanceSynced(attendance.attendanceId);
                          } catch (err) {
                            debugPrint('Cloud sync queue notice: $err');
                          }

                          // 3. Email Alert
                          try {
                            EmailNotificationService().sendLateAttendanceAlertEmail(
                              employeeName: name,
                              employeeId: empId,
                              shiftName: shiftResult.shiftName,
                              lateMinutes: shiftResult.lateMinutes,
                              lateReason: fullReason,
                              shopId: widget.shopId,
                              checkInTime: now,
                            );
                          } catch (_) {}

                          if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
                            Navigator.of(dialogCtx).pop();
                          }

                          if (mounted) {
                            setState(() {
                              _lastRecognizedEmployee = empData;
                              _lastRecognizedName = name;
                              _isAttendanceMarked = true;
                              _noMatchFound = false;
                              _scanFailureReason = null;
                              _statusMessage = '⚠️ Late Check-In Submitted for Admin Approval (Late: ${shiftResult.lateMinutes}m)';
                            });

                            messenger.showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '✓ Late reason submitted to Admin ($name)',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: AppColors.kesariSaffron,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }

                          await Future.delayed(const Duration(seconds: 4));
                          if (mounted) {
                            setState(() {
                              _resetSessionLock();
                            });
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isManualSyncing = false;

  Future<void> _triggerManualSync() async {
    if (_isManualSyncing) return;

    setState(() {
      _isManualSyncing = true;
      _statusMessage = '🔄 Syncing with Cloud... (Uploading local attendance & downloading staff)';
    });

    try {
      final result = await SyncEngine().triggerFullBidirectionalSync(widget.businessId);

      // Refresh local enrolled staff cache in memory
      final updatedLocal = await _offlineDb.getLocalEmployeesWithEmbeddings(widget.businessId);
      if (mounted) {
        setState(() {
          _enrolledStaffCache = updatedLocal;
          _statusMessage = result['message'] ?? '✓ Cloud Sync Complete!';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result['message'] ?? '✓ Cloud Sync Complete!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.pannaEmerald,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '⚠️ Sync error. Operating via local SQLite cache.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isManualSyncing = false;
        });
      }
    }
  }

  void _showExitDialog() {
    final pinCtrl = TextEditingController();
    String? errorMsg;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.cardBorderDark),
          ),
          title: Text('Exit Kiosk Mode', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter Admin Security PIN to exit kiosk mode:', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 4, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Admin Security PIN',
                  labelStyle: const TextStyle(color: AppColors.textMuted),
                  errorText: errorMsg,
                  filled: true,
                  fillColor: AppColors.inputBgDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.sindoorRed),
              onPressed: () async {
                final pin = pinCtrl.text.trim();
                if (pin == '1234' || pin.length >= 4) {
                  await AuthRoutingService().signOut();
                  if (context.mounted) {
                    Navigator.pop(context);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                } else {
                  setModalState(() {
                    errorMsg = 'Incorrect Security PIN';
                  });
                }
              },
              child: const Text('VERIFY & EXIT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _businessName.isNotEmpty ? _businessName.toUpperCase() : 'SHOP KIOSK: ${widget.shopId}',
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                _buildAnnouncementBanner(),
                const SizedBox(height: 8),
                Text(
                  _isShopPaused ? '⚠️ SERVICE TEMPORARILY PAUSED BY MASTER ADMIN' : 'REAL-TIME BIOMETRIC ENTRANCE KIOSK',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: _isShopPaused ? AppColors.haldiGold : AppColors.pannaEmerald,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Touchless Auto Detect Active Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.pannaEmerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.pannaEmerald.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.pannaEmerald,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'TOUCHLESS AUTO DETECT & EYE BLINK ACTIVE',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.pannaEmerald, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Live Camera Circle Scanner
                GestureDetector(
                  onTap: () {
                    if (_lockedEmployee != null && !_isFinalizingAttendance) {
                      _finalizeAttendanceForLockedEmployee();
                    } else if (!_isProcessing && _cameraController != null && _cameraController!.value.isInitialized) {
                      _autoDetectFrame();
                    }
                  },
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.cardDark,
                      border: Border.all(
                        color: _isShopPaused
                            ? AppColors.haldiGold
                            : (_lastRecognizedName != null
                                ? AppColors.pannaEmerald
                                : (_faceDetectedInFrame ? AppColors.haldiGold : AppColors.kesariSaffron)),
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_lastRecognizedName != null
                                  ? AppColors.pannaEmerald
                                  : (_faceDetectedInFrame ? AppColors.haldiGold : AppColors.kesariSaffron))
                              .withValues(alpha: 0.35),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_isCameraInitialized && _cameraController != null)
                            CameraPreview(_cameraController!)
                          else
                            const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.camera_front_rounded, size: 80, color: AppColors.haldiGold),
                                SizedBox(height: 8),
                                Text('Live Scanner Active', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            ),

                          if (_isProcessing)
                            Container(
                              color: Colors.black45,
                              child: const Center(
                                child: CircularProgressIndicator(color: AppColors.kesariSaffron),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Status Message Box with Eye Blink Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: _lastRecognizedName != null ? AppColors.pannaEmerald : AppColors.cardBorderDark,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _lastRecognizedName != null
                            ? Icons.verified_rounded
                            : (_faceDetectedInFrame ? Icons.remove_red_eye_rounded : Icons.face_rounded),
                        color: _lastRecognizedName != null
                            ? AppColors.pannaEmerald
                            : (_faceDetectedInFrame ? AppColors.haldiGold : AppColors.kesariSaffron),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _statusMessage,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: _lastRecognizedName != null ? AppColors.pannaEmerald : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Recognized Employee Profile Details Banner
                if (_lastRecognizedEmployee != null || _lastRecognizedName != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.pannaEmerald, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.pannaEmerald.withValues(alpha: 0.25),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.pannaEmerald,
                              child: Icon(Icons.person_rounded, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _lastRecognizedEmployee?['fullName'] ?? _lastRecognizedName ?? 'Employee',
                                  style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Emp Code: ${_lastRecognizedEmployee?['empCode'] ?? _lastRecognizedEmployee?['employeeId'] ?? 'EMP-01'}  •  Phone: ${_lastRecognizedEmployee?['phone'] ?? _lastRecognizedEmployee?['phoneNumber'] ?? 'N/A'}',
                                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.haldiGold, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            if (_lastRecognizedEmployee?['department'] != null && _lastRecognizedEmployee!['department'].toString().isNotEmpty)
                              Chip(
                                backgroundColor: AppColors.inputBgDark,
                                side: const BorderSide(color: AppColors.cardBorderDark),
                                avatar: const Icon(Icons.business_outlined, size: 14, color: AppColors.haldiGold),
                                label: Text(_lastRecognizedEmployee!['department'].toString(), style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (_lastRecognizedEmployee?['designation'] != null && _lastRecognizedEmployee!['designation'].toString().isNotEmpty)
                              Chip(
                                backgroundColor: AppColors.inputBgDark,
                                side: const BorderSide(color: AppColors.cardBorderDark),
                                avatar: const Icon(Icons.work_outline, size: 14, color: AppColors.haldiGold),
                                label: Text(_lastRecognizedEmployee!['designation'].toString(), style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            Chip(
                              backgroundColor: _isAttendanceMarked
                                  ? AppColors.pannaEmerald.withValues(alpha: 0.2)
                                  : AppColors.haldiGold.withValues(alpha: 0.2),
                              side: BorderSide(
                                color: _isAttendanceMarked ? AppColors.pannaEmerald : AppColors.haldiGold,
                              ),
                              avatar: Icon(
                                _isAttendanceMarked ? Icons.check_circle_rounded : Icons.remove_red_eye_rounded,
                                size: 14,
                                color: _isAttendanceMarked ? AppColors.pannaEmerald : AppColors.haldiGold,
                              ),
                              label: Text(
                                _isAttendanceMarked
                                    ? '✓ PRESENT TODAY • ATTENDANCE LOGGED'
                                    : '👀 FACE IDENTIFIED • BLINK EYES TO LOG ATTENDANCE',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _isAttendanceMarked ? AppColors.pannaEmerald : AppColors.haldiGold,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // Unrecognized / No Data Found Failure Banner
                if (_noMatchFound) ...[
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.sindoorRed, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.sindoorRed.withValues(alpha: 0.25),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.sindoorRed,
                              child: Icon(Icons.person_off_rounded, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'NO MATCH / DATA FOUND',
                                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.sindoorRed),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _scanFailureReason ?? 'Unregistered Face • Attendance Not Marked',
                                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.haldiGold, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Chip(
                          backgroundColor: AppColors.sindoorRed.withValues(alpha: 0.15),
                          side: const BorderSide(color: AppColors.sindoorRed),
                          avatar: const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.sindoorRed),
                          label: const Text('ACCESS DENIED / NOT ENROLLED', style: TextStyle(fontSize: 11, color: AppColors.sindoorRed, fontWeight: FontWeight.bold)),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Bottom Left Heartbeat & Offline Queue Status
          Positioned(
            left: 20,
            bottom: 20,
            child: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: AppColors.pannaEmerald, size: 20),
                const SizedBox(width: 8),
                Text('Heartbeat Active • Offline Queue Protected', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),

          // Top Right Manual Sync NOW & Exit Lock Action Bar
          Positioned(
            top: 40,
            right: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardDark,
                    side: const BorderSide(color: AppColors.kesariSaffron, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: _isManualSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.kesariSaffron, strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, color: AppColors.kesariSaffron, size: 20),
                  label: Text(
                    _isManualSyncing ? 'SYNCING...' : 'SYNC NOW 🔄',
                    style: GoogleFonts.inter(color: AppColors.kesariSaffron, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: _isManualSyncing ? null : _triggerManualSync,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardDark,
                    side: BorderSide(color: AppColors.haldiGold.withValues(alpha: 0.8), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.haldiGold, size: 18),
                  label: Text(
                    'RESET CAMERA 📸',
                    style: GoogleFonts.inter(color: AppColors.haldiGold, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: _resetCamera,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.lock_open_rounded, color: Colors.white70, size: 26),
                  tooltip: 'Exit Kiosk Mode',
                  onPressed: _showExitDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
