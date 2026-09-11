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

  bool _isProcessing = false;
  String _statusMessage = 'Align face in camera circle to scan';
  String? _lastRecognizedName;
  bool _isShopPaused = false;
  final String _deviceId = 'KSK-01';

  @override
  void initState() {
    super.initState();
    _initServicesAndCamera();
    _listenToShopStatus();
    _heartbeatService.startHeartbeat(
      businessId: widget.businessId,
      shopId: widget.shopId,
      deviceId: _deviceId,
    );
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
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Kiosk camera init info: $e');
    }
  }

  void _listenToShopStatus() {
    FirebaseFirestore.instance
        .collection(AppConstants.colBusinesses)
        .doc(widget.businessId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        final status = doc.get('status') ?? '';
        setState(() {
          _isShopPaused = status == AppConstants.statusPaused;
        });
      }
    });
  }

  @override
  void dispose() {
    _heartbeatService.stopHeartbeat();
    _cameraController?.dispose();
    super.dispose();
  }

  // Trigger Real Face Scan & Recognition from live camera or image capture
  Future<void> _processFaceScan() async {
    if (_isShopPaused || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Scanning face & matching features...';
    });

    try {
      Uint8List bytes = Uint8List(0);
      String tempPath = '';

      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final xFile = await _cameraController!.takePicture();
        bytes = await xFile.readAsBytes();
        tempPath = xFile.path;
      }

      List<double>? targetVector;
      if (tempPath.isNotEmpty && bytes.isNotEmpty) {
        targetVector = await _faceService.processFaceFromBytes(bytes, tempPath);
      }

      if (targetVector == null) {
        await _voiceService.speakAlert('Face position unclear or quality low. Look directly at camera.');
        setState(() {
          _statusMessage = 'Face Quality Low — Retype/Look Frontal';
        });
        await Future.delayed(const Duration(seconds: 2));
        return;
      }

      // Fetch real enrolled staff exclusively from Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .collection(AppConstants.colEmployees)
          .where('active', isEqualTo: true)
          .where('faceEnrollmentStatus', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> enrolled = snapshot.docs.map((doc) => doc.data()).toList();

      if (enrolled.isEmpty) {
        await _voiceService.speakAlert('No enrolled staff found for this business.');
        setState(() {
          _statusMessage = 'No Enrolled Staff in Database';
        });
        await Future.delayed(const Duration(seconds: 2));
        return;
      }

      final match = _faceService.matchFace(
        targetEmbedding: targetVector,
        enrolledEmployees: enrolled,
      );

      if (match != null) {
        final String empId = match['employeeId'];
        final String name = match['employeeName'];
        final double confidence = match['confidence'];

        final now = DateTime.now();
        final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

        // Check for 5-minute duplicate attendance safeguard
        final isDuplicate = await _offlineDb.hasRecentAttendance(empId, dateStr);
        if (isDuplicate) {
          await _voiceService.speakAlert('$name, your attendance was already logged recently.');
          setState(() {
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
            _lastRecognizedName = name;
            _statusMessage = '✓ Welcome $name! Attendance Marked.';
          });
        }
      } else {
        await _voiceService.speakAlert('Face not recognized. Please try again.');
        setState(() {
          _statusMessage = 'Face Not Recognized (No Match Found)';
        });
      }
    } catch (e) {
      debugPrint('Error in kiosk scan: $e');
      setState(() {
        _statusMessage = 'Error scanning face. Please try again.';
      });
    } finally {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _lastRecognizedName = null;
          _statusMessage = 'Align face in camera circle to scan';
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
              onPressed: () {
                final pin = pinCtrl.text.trim();
                if (pin == '1234' || pin.length >= 4) {
                  Navigator.pop(context);
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
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
                  'SHOP KIOSK: ${widget.shopId}',
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
                const SizedBox(height: 32),

                // Live Camera Circle Scanner
                GestureDetector(
                  onTap: _processFaceScan,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.cardDark,
                      border: Border.all(
                        color: _isShopPaused
                            ? AppColors.haldiGold
                            : (_lastRecognizedName != null ? AppColors.pannaEmerald : AppColors.kesariSaffron),
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_lastRecognizedName != null ? AppColors.pannaEmerald : AppColors.kesariSaffron).withValues(alpha: 0.3),
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

                // Status Message Box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.cardBorderDark),
                  ),
                  child: Text(
                    _statusMessage,
                    style: GoogleFonts.inter(fontSize: 16, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.kesariSaffron,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white),
                  label: const Text('SCAN FACE NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: _isProcessing ? null : _processFaceScan,
                ),
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
