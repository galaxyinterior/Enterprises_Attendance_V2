import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/face_recognition_service.dart';
import '../../core/services/offline_db_service.dart';
import '../../models/employee_model.dart';



class EditEmployeeScreen extends StatefulWidget {
  final String businessId;
  final String shopId;
  final EmployeeModel employee;

  const EditEmployeeScreen({
    super.key,
    required this.businessId,
    required this.shopId,
    required this.employee,
  });

  @override
  State<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  late TextEditingController _fullNameCtrl;
  late TextEditingController _empCodeCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _departmentCtrl;
  late TextEditingController _designationCtrl;
  late TextEditingController _salaryCtrl;
  late DateTime _joiningDate;
  late String _selectedShift;

  // Camera & Face Registration State
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraInitialized = false;
  bool _isCapturingFace = false;
  Uint8List? _capturedFaceBytes;

  List<double>? _synthesizedFaceEmbedding;
  String _faceStatusMessage = 'Look straight at camera & tap Capture 😐';
  bool _isSaving = false;

  final _faceService = FaceRecognitionService();

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController(text: widget.employee.fullName);
    _empCodeCtrl = TextEditingController(text: widget.employee.employeeCode);
    _phoneCtrl = TextEditingController(text: widget.employee.phone);
    _departmentCtrl = TextEditingController(text: widget.employee.department);
    _designationCtrl = TextEditingController(text: widget.employee.designation);
    _salaryCtrl = TextEditingController(text: widget.employee.monthlySalary.toStringAsFixed(0));
    _joiningDate = widget.employee.joiningDate;
    _selectedShift = widget.employee.assignedShiftId.isNotEmpty
        ? widget.employee.assignedShiftId
        : 'Morning Shift (10:00 AM - 06:30 PM)';

    _synthesizedFaceEmbedding = widget.employee.faceEmbedding;
    if (_synthesizedFaceEmbedding != null && _synthesizedFaceEmbedding!.isNotEmpty) {
      _faceStatusMessage = '✓ Existing Face Profile Registered (${_synthesizedFaceEmbedding!.length}D)';
    }

    _initCameraAndFaceService();
  }

  Future<void> _initCameraAndFaceService() async {
    await _faceService.initialize();
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isNotEmpty) {
        final frontCam = _availableCameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.front,
          orElse: () => _availableCameras.first,
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
      debugPrint('Camera initialization info: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _fullNameCtrl.dispose();
    _empCodeCtrl.dispose();
    _phoneCtrl.dispose();
    _departmentCtrl.dispose();
    _designationCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  // Single-Step Straight Face Capture
  Future<void> _captureGuidedStepFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() {
        _faceStatusMessage = '❌ Camera not ready. Please check camera permission.';
      });
      return;
    }

    setState(() {
      _isCapturingFace = true;
    });

    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      final res = await _faceService.processFaceFromBytesDetailed(
        bytes: bytes,
        tempFilePath: xFile.path,
        context: 'EDIT_ENROLLMENT_STRAIGHT',
        employeeId: _empCodeCtrl.text.trim(),
      );

      if (res['success'] == true && res['embedding'] != null) {
        final List<double> vec = res['embedding'] as List<double>;

        // Check for duplicate face enrollment excluding current employee
        final existingStaff = await OfflineDbService().getLocalEmployees();
        final dupCheck = await _faceService.checkDuplicateEnrolledFace(
          newEmbedding: vec,
          existingEmployees: existingStaff,
          excludeEmployeeId: widget.employee.employeeId,
        );

        if (dupCheck != null && dupCheck['isDuplicate'] == true) {
          final String matchedName = dupCheck['matchedEmployeeName'] ?? 'Existing Staff';
          setState(() {
            _capturedFaceBytes = null;
            _synthesizedFaceEmbedding = null;
            _faceStatusMessage = '❌ Duplicate Face Detected! Already registered for "$matchedName".';
          });
          return;
        }

        setState(() {
          _capturedFaceBytes = bytes;
          _synthesizedFaceEmbedding = vec;
          _faceStatusMessage = '✓ Face Profile Updated Successfully (${vec.length}D Ready)';
        });
      } else {
        final String err = res['error'] ?? 'Face not detected clearly';
        setState(() {
          _faceStatusMessage = '❌ $err';
        });
      }
    } catch (e) {
      setState(() {
        _faceStatusMessage = '❌ Capture error: $e';
      });
    } finally {
      setState(() {
        _isCapturingFace = false;
      });
    }
  }

  void _resetGuidedEnrollment() {
    setState(() {
      _synthesizedFaceEmbedding = null;
      _capturedFaceBytes = null;
      _faceStatusMessage = 'Look straight at camera & tap Capture 😐';
    });
  }

  Future<void> _updateEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    if (_synthesizedFaceEmbedding == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete multi-angle face enrollment before saving!'),
          backgroundColor: AppColors.haldiGold,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final double salary = double.tryParse(_salaryCtrl.text.trim()) ?? widget.employee.monthlySalary;

      final updatedEmployee = EmployeeModel(
        employeeId: widget.employee.employeeId,
        businessId: widget.businessId,
        employeeCode: _empCodeCtrl.text.trim().toUpperCase(),
        fullName: _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        department: _departmentCtrl.text.trim(),
        designation: _designationCtrl.text.trim(),
        assignedShiftId: _selectedShift,
        joiningDate: _joiningDate,
        monthlySalary: salary,
        active: widget.employee.active,
        faceEnrollmentStatus: true,
        faceEmbedding: _synthesizedFaceEmbedding,
        createdAt: widget.employee.createdAt,
        updatedAt: DateTime.now(),
      );

      final empMap = updatedEmployee.toMap();

      // 1. Update in Firestore
      await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .collection(AppConstants.colEmployees)
          .doc(widget.employee.employeeId)
          .update(empMap);

      // 2. Sync updated employee locally in SQLite DB
      await OfflineDbService().saveLocalEmployees([empMap]);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Employee "${updatedEmployee.fullName}" updated & synced!'),
          backgroundColor: AppColors.pannaEmerald,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating employee: $e'), backgroundColor: AppColors.sindoorRed),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.cardDark,
        title: Text(
          'Edit Employee: ${widget.employee.fullName}',
          style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Form(
              key: _formKey,
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildFormSection(isMobile: false)),
                        const SizedBox(width: 20),
                        Expanded(flex: 2, child: _buildGuidedFaceCaptureSection()),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFormSection(isMobile: true),
                        const SizedBox(height: 20),
                        _buildGuidedFaceCaptureSection(),
                      ],
                    ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
          border: Border(top: BorderSide(color: AppColors.cardBorderDark)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    side: const BorderSide(color: AppColors.cardBorderDark),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.saffronGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                    label: Text(
                      _isSaving ? 'UPDATING...' : 'SAVE & UPDATE EMPLOYEE',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: _isSaving ? null : _updateEmployee,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection({required bool isMobile}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppColors.haldiGold, size: 22),
              const SizedBox(width: 10),
              Text(
                '1. Edit Employee Details',
                style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildInputField(_fullNameCtrl, 'Full Name *', Icons.person_outline, validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter full name' : null),

          if (isMobile) ...[
            _buildInputField(_empCodeCtrl, 'Employee Code *', Icons.tag, validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null),
            _buildInputField(_phoneCtrl, 'Phone Number *', Icons.phone_outlined, keyboardType: TextInputType.phone, validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null),
            _buildInputField(_departmentCtrl, 'Department', Icons.business_outlined),
            _buildInputField(_designationCtrl, 'Designation', Icons.work_outline),
            _buildInputField(_salaryCtrl, 'Monthly Salary (₹)', Icons.currency_rupee_rounded, keyboardType: TextInputType.number),
            _buildShiftDropdown(),
          ] else ...[
            Row(
              children: [
                Expanded(child: _buildInputField(_empCodeCtrl, 'Employee Code *', Icons.tag, validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null)),
                const SizedBox(width: 12),
                Expanded(child: _buildInputField(_phoneCtrl, 'Phone Number *', Icons.phone_outlined, keyboardType: TextInputType.phone, validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null)),
              ],
            ),
            Row(
              children: [
                Expanded(child: _buildInputField(_departmentCtrl, 'Department', Icons.business_outlined)),
                const SizedBox(width: 12),
                Expanded(child: _buildInputField(_designationCtrl, 'Designation', Icons.work_outline)),
              ],
            ),
            Row(
              children: [
                Expanded(child: _buildInputField(_salaryCtrl, 'Monthly Salary (₹)', Icons.currency_rupee_rounded, keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _buildShiftDropdown()),
              ],
            ),
          ],

          const SizedBox(height: 10),
          Text('Joining Date', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _joiningDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _joiningDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.inputBgDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorderDark),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: AppColors.haldiGold, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('dd MMMM yyyy').format(_joiningDate),
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Assigned Shift', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(AppConstants.colBusinesses)
                .doc(widget.businessId)
                .collection('shifts')
                .snapshots(),
            builder: (context, snapshot) {
              List<DropdownMenuItem<String>> items = [];

              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['shiftName'] ?? 'Shift';
                  final start = data['startTime'] ?? '';
                  final end = data['endTime'] ?? '';
                  final label = '$name ($start - $end)';
                  items.add(DropdownMenuItem(value: name, child: Text(label)));
                }
              }

              // Fallback default options if no custom shifts configured
              if (items.isEmpty) {
                items = [
                  DropdownMenuItem(value: _selectedShift, child: Text(_selectedShift)),
                  const DropdownMenuItem(value: 'General Shift (09:00 AM - 06:00 PM)', child: Text('General Shift (9 AM - 6 PM)')),
                  const DropdownMenuItem(value: 'Morning Shift (10:00 AM - 06:30 PM)', child: Text('Morning Shift (10 AM - 6:30 PM)')),
                  const DropdownMenuItem(value: 'Evening Shift (02:00 PM - 10:30 PM)', child: Text('Evening Shift (2 PM - 10:30 PM)')),
                  const DropdownMenuItem(value: 'Night Shift (09:00 PM - 06:00 AM)', child: Text('Night Shift (9 PM - 6 AM)')),
                ];
              }

              // Ensure selected shift is valid
              String value = _selectedShift;
              if (!items.any((item) => item.value == value)) {
                items.insert(0, DropdownMenuItem(value: value, child: Text(value)));
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.inputBgDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorderDark),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: AppColors.cardDark,
                    isExpanded: true,
                    value: value,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    items: items,
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedShift = val);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGuidedFaceCaptureSection() {
    final bool isEnrolled = _synthesizedFaceEmbedding != null && _synthesizedFaceEmbedding!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.center_focus_strong_rounded, color: AppColors.pannaEmerald, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    '2. Face Enrolment',
                    style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (isEnrolled)
                TextButton.icon(
                  icon: const Icon(Icons.restart_alt_rounded, size: 16, color: AppColors.haldiGold),
                  label: const Text('RESET', style: TextStyle(color: AppColors.haldiGold, fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: _resetGuidedEnrollment,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Look straight at the camera to record face feature vector for attendance.',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Camera Frame Box
          Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.inputBgDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isEnrolled ? AppColors.pannaEmerald : AppColors.kesariSaffron,
                width: isEnrolled ? 2.5 : 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_capturedFaceBytes != null && _capturedFaceBytes!.isNotEmpty)
                    Image.memory(_capturedFaceBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                  else if (_isCameraInitialized && _cameraController != null)
                    CameraPreview(_cameraController!)
                  else
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_front_rounded, color: AppColors.haldiGold, size: 50),
                        SizedBox(height: 8),
                        Text('Camera Active', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                      ],
                    ),

                  // Alignment Circle
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isEnrolled ? AppColors.pannaEmerald : AppColors.kesariSaffron,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        isEnrolled ? '✓' : '😐',
                        style: TextStyle(fontSize: 38, color: isEnrolled ? AppColors.pannaEmerald : Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Step Feedback Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isEnrolled
                  ? AppColors.pannaEmerald.withValues(alpha: 0.15)
                  : AppColors.inputBgDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isEnrolled ? AppColors.pannaEmerald : AppColors.cardBorderDark,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isEnrolled ? Icons.verified_rounded : Icons.info_outline_rounded,
                  color: isEnrolled ? AppColors.pannaEmerald : AppColors.haldiGold,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _faceStatusMessage,
                    style: GoogleFonts.inter(
                      color: isEnrolled ? AppColors.pannaEmerald : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isEnrolled ? AppColors.haldiGold : AppColors.pannaEmerald,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isCapturingFace
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Icon(isEnrolled ? Icons.refresh_rounded : Icons.camera_alt_rounded, color: Colors.white, size: 20),
              label: Text(
                _isCapturingFace
                    ? 'EXTRACTING VECTOR...'
                    : (isEnrolled ? 'RE-CAPTURE STRAIGHT FACE' : 'CAPTURE STRAIGHT FACE'),
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
              onPressed: _isCapturingFace
                  ? null
                  : (isEnrolled ? _resetGuidedEnrollment : _captureGuidedStepFace),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.haldiGold, size: 20),
          filled: true,
          fillColor: AppColors.inputBgDark,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.cardBorderDark),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.cardBorderDark),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.kesariSaffron),
          ),
        ),
        validator: validator,
      ),
    );
  }
}
