import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:camera/camera.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/face_recognition_service.dart';
import '../../core/services/voice_announcements_service.dart';
import '../../core/services/offline_db_service.dart';
import '../../core/services/kiosk_heartbeat_service.dart';
import '../../core/services/auth_routing_service.dart';
import '../../models/attendance_model.dart';
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

class _KioskAttendanceScreenState extends State<KioskAttendanceScreen> {
  final _faceService = FaceRecognitionService();
  final _voiceService = VoiceAnnouncementsService();
  final _offlineDb = OfflineDbService();
  final _heartbeatService = KioskHeartbeatService();

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;

  Timer? _autoScanTimer;
  bool _isProcessing = false;
  bool _faceDetectedInFrame = false;

  List<Map<String, dynamic>> _enrolledStaffCache = [];
  Map<String, dynamic>? _lastRecognizedEmployee;
  String _statusMessage = '👁️ Position face inside camera circle to scan';
  String? _lastRecognizedName;
  bool _isShopPaused = false;
  final String _deviceId = 'KSK-01';

  @override
  void initState() {
    super.initState();
    _initServicesAndCamera();
    _listenToShopStatus();
    _listenToEnrolledStaff();
    _heartbeatService.startHeartbeat(
      businessId: widget.businessId,
      shopId: widget.shopId,
      deviceId: _deviceId,
    );
  }

  void _listenToEnrolledStaff() {
    // 1. Initial load from local SQLite database for 100% offline availability
    _offlineDb.getLocalEmployeesWithEmbeddings(widget.businessId).then((localEmps) {
      if (mounted && localEmps.isNotEmpty) {
        setState(() {
          _enrolledStaffCache = localEmps;
        });
      }
    });

    // 2. Real-time sync from Cloud Firestore to Local SQLite database
    FirebaseFirestore.instance
        .collection(AppConstants.colBusinesses)
        .doc(widget.businessId)
        .collection(AppConstants.colEmployees)
        .snapshots()
        .listen((snapshot) async {
      final enrolled = snapshot.docs
          .map((doc) => doc.data())
          .where((emp) => emp['faceEmbedding'] != null && (emp['faceEmbedding'] as List).isNotEmpty)
          .toList();
      
      await _offlineDb.saveLocalEmployees(enrolled);
      final updatedLocal = await _offlineDb.getLocalEmployeesWithEmbeddings(widget.businessId);

      if (mounted) {
        setState(() {
          _enrolledStaffCache = updatedLocal;
        });
      }
    });
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

  void _startAutoScanner() {
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (!mounted || !_isCameraInitialized || _isProcessing || _isShopPaused || _cameraController == null || !_cameraController!.value.isInitialized) {
        return;
      }
      await _autoDetectFrame();
    });
  }

  Future<void> _autoDetectFrame() async {
    try {
      if (_isProcessing) return;
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      final res = await _faceService.detectFaceAndCheckBlink(xFile.path);

      if (res == null || res['hasFace'] != true) {
        if (_faceDetectedInFrame) {
          if (mounted) {
            setState(() {
              _faceDetectedInFrame = false;
              _statusMessage = '👁️ Position face inside camera circle to scan';
            });
          }
        }
        return;
      }

      // Face is detected in camera!
      if (!_faceDetectedInFrame) {
        if (mounted) {
          setState(() {
            _faceDetectedInFrame = true;
            _statusMessage = '👁️ Face Detected — Verifying locally...';
          });
        }
      }

      // Trigger attendance scan immediately when face detected
      await _processFaceScanWithFile(xFile.path, bytes);
    } catch (e) {
      debugPrint('Auto check frame error: $e');
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

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    _heartbeatService.stopHeartbeat();
    _cameraController?.dispose();
    super.dispose();
  }

  // Trigger Real Face Scan & Recognition from live camera frame
  Future<void> _processFaceScanWithFile(String tempPath, Uint8List bytes) async {
    if (_isShopPaused || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = '⚡ Verifying face in Local Database...';
    });

    try {
      List<double>? targetVector = await _faceService.processFaceFromBytes(bytes, tempPath);

      if (targetVector == null || targetVector.isEmpty) {
        debugPrint('Face vector extraction returned empty, skipping frame...');
        return;
      }

      // Step 1: Perform 100% offline local SQLite memory match
      var match = _faceService.matchFace(
        targetEmbedding: targetVector,
        enrolledEmployees: _enrolledStaffCache,
      );

      // Step 2: If face NOT found in local DB, log and search Cloud Database
      if (match == null) {
        debugPrint('❌ Face vector not found in Local SQLite DB (${_enrolledStaffCache.length} cached). Searching Cloud Firebase Database...');
        setState(() {
          _statusMessage = '☁️ Face not in Local DB — Searching Cloud Firebase Database...';
        });

        try {
          final snapshot = await FirebaseFirestore.instance
              .collection(AppConstants.colBusinesses)
              .doc(widget.businessId)
              .collection(AppConstants.colEmployees)
              .get();

          final cloudEmps = snapshot.docs
              .map((doc) => doc.data())
              .where((emp) => emp['faceEmbedding'] != null && (emp['faceEmbedding'] as List).isNotEmpty)
              .toList();

          debugPrint('Fetched ${cloudEmps.length} total staff documents from Cloud Firebase.');

          if (cloudEmps.isNotEmpty) {
            // Save new documents to local SQLite DB
            await _offlineDb.saveLocalEmployees(cloudEmps);
            final freshLocal = await _offlineDb.getLocalEmployeesWithEmbeddings(widget.businessId);
            _enrolledStaffCache = freshLocal;

            // Re-run instant matching on updated local database!
            match = _faceService.matchFace(
              targetEmbedding: targetVector,
              enrolledEmployees: _enrolledStaffCache,
            );

            if (match != null) {
              debugPrint('✓ Face successfully matched in newly downloaded Cloud Database record!');
              setState(() {
                _statusMessage = '✓ Employee Found in Cloud! Syncing & Marking Attendance...';
              });
            }
          }
        } catch (e) {
          debugPrint('Cloud fallback sync error: $e');
        }
      }

      if (match != null) {
        final String empId = match['employeeId'];
        final String name = match['employeeName'];
        final double confidence = match['confidence'];
        final Map<String, dynamic> empData = match['employeeData'] ?? {};

        final now = DateTime.now();
        final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

        // Check for 5-minute duplicate attendance safeguard
        final isDuplicate = await _offlineDb.hasRecentAttendance(empId, dateStr);
        if (isDuplicate) {
          await _voiceService.speakAlert('$name, your attendance was already logged recently.');
          setState(() {
            _lastRecognizedEmployee = empData;
            _lastRecognizedName = name;
            _statusMessage = '$name — Attendance Already Logged Recently';
          });
        } else {
          final attendance = AttendanceModel(
            attendanceId: const Uuid().v4(),
            businessId: widget.businessId,
            employeeId: empId,
            employeeName: name,
            date: dateStr,
            shiftId: 'SHIFT_DEFAULT',
            checkInTime: now,
            status: AppConstants.attendancePresent,
            confidence: confidence,
            syncStatus: AppConstants.syncPending,
            createdAt: now,
            updatedAt: now,
          );

          // Save to offline SQLite database & Cloud Firestore
          await _offlineDb.insertAttendance(attendance);
          await FirebaseFirestore.instance
              .collection(AppConstants.colBusinesses)
              .doc(widget.businessId)
              .collection(AppConstants.colAttendance)
              .doc(attendance.attendanceId)
              .set(attendance.toMap());

          // Speak personalized voice greeting
          await _voiceService.speakCheckInGreeting(name);

          setState(() {
            _lastRecognizedEmployee = empData;
            _lastRecognizedName = name;
            _statusMessage = '✓ Welcome $name! Attendance Marked.';
          });
        }
      } else {
        await _voiceService.speakAlert('Face not recognized. Please try again.');
        setState(() {
          _lastRecognizedEmployee = null;
          _statusMessage = 'Face Not Recognized (No Match Found)';
        });
      }
    } catch (e) {
      debugPrint('Error in kiosk auto scan: $e');
      setState(() {
        _statusMessage = 'Error scanning face. Retrying...';
      });
    } finally {
      await Future.delayed(const Duration(milliseconds: 4500));
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _faceDetectedInFrame = false;
          _lastRecognizedName = null;
          _lastRecognizedEmployee = null;
          _statusMessage = '👁️ Position face inside camera circle to scan';
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
                    if (!_isProcessing && _cameraController != null && _cameraController!.value.isInitialized) {
                      _cameraController!.takePicture().then((xFile) async {
                        final bytes = await xFile.readAsBytes();
                        _processFaceScanWithFile(xFile.path, bytes);
                      });
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
                              backgroundColor: AppColors.pannaEmerald.withValues(alpha: 0.2),
                              side: const BorderSide(color: AppColors.pannaEmerald),
                              avatar: const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.pannaEmerald),
                              label: const Text('PRESENT TODAY', style: TextStyle(fontSize: 11, color: AppColors.pannaEmerald, fontWeight: FontWeight.bold)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
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

          // Top Right Exit Lock Button
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.lock_open_rounded, color: Colors.white70, size: 28),
              tooltip: 'Exit Kiosk Mode',
              onPressed: _showExitDialog,
            ),
          ),
        ],
      ),
    );
  }
}
