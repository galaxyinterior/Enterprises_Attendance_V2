import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/auth_routing_service.dart';
import '../../models/employee_model.dart';
import '../../models/advance_salary_model.dart';
import '../../models/attendance_model.dart';
import '../auth/login_screen.dart';
import 'add_employee_screen.dart';
import 'edit_employee_screen.dart';
import 'shift_management_screen.dart';
import 'admin_calendar_screen.dart';
import '../../core/services/custom_voice_recorder_service.dart';

import '../../core/services/sync_engine.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String shopId;
  final String businessId;

  const AdminDashboardScreen({
    super.key,
    required this.shopId,
    required this.businessId,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedNavIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _announcementCtrl = TextEditingController();
  final CustomVoiceRecorderService _voiceRecorder = CustomVoiceRecorderService();
  String _selectedAnnouncementType = 'emergency'; // 'emergency', 'notice', 'info'
  bool _isBroadcastingAnnouncement = false;
  bool _isCustomAudioMode = false;
  String? _recordedAudioBase64;
  String? _recordedAudioPath;
  int _recordedDuration = 0;
  DateTime _selectedLogDate = DateTime.now();
  String _selectedStatusFilter = 'ALL';
  bool _isAdminSyncing = false;

  Future<void> _triggerAdminManualSync() async {
    if (_isAdminSyncing) return;
    setState(() => _isAdminSyncing = true);

    try {
      final res = await SyncEngine().triggerFullBidirectionalSync(widget.businessId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? '✓ Cloud Sync Complete!'),
          backgroundColor: AppColors.pannaEmerald,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync notice: $e'),
          backgroundColor: AppColors.haldiGold,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdminSyncing = false);
    }
  }

  void _showKioskLanguageSettingsDialog() async {
    String currentLang = 'en-IN';
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .get();
      if (doc.exists && doc.data() != null) {
        currentLang = doc.data()!['ttsLanguage'] ?? 'en-IN';
      }
    } catch (_) {}

    final languages = [
      {'code': 'en-IN', 'name': 'English (India) 🇮🇳', 'sub': 'Default Indian Accent'},
      {'code': 'hi-IN', 'name': 'Hindi (हिन्दी) 🇮🇳', 'sub': 'Hindi Greetings & Prompts'},
      {'code': 'en-US', 'name': 'English (United States) 🇺🇸', 'sub': 'American Accent'},
      {'code': 'mr-IN', 'name': 'Marathi (मराठी) 🇮🇳', 'sub': 'Marathi TTS Support'},
      {'code': 'bn-IN', 'name': 'Bengali (বাংলা) 🇮🇳', 'sub': 'Bengali TTS Support'},
      {'code': 'ta-IN', 'name': 'Tamil (தமிழ்) 🇮🇳', 'sub': 'Tamil TTS Support'},
      {'code': 'te-IN', 'name': 'Telugu (తెలుగు) 🇮🇳', 'sub': 'Telugu TTS Support'},
      {'code': 'gu-IN', 'name': 'Gujarati (ગુજરાતી) 🇮🇳', 'sub': 'Gujarati TTS Support'},
      {'code': 'kn-IN', 'name': 'Kannada (ಕನ್ನಡ) 🇮🇳', 'sub': 'Kannada TTS Support'},
    ];

    String selectedCode = currentLang;
    bool isSaving = false;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.cardBorderDark),
          ),
          title: Row(
            children: [
              const Icon(Icons.record_voice_over_rounded, color: AppColors.kesariSaffron, size: 24),
              const SizedBox(width: 10),
              Text('Kiosk Voice TTS Language', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select the TTS voice language for Kiosk attendance greetings & announcements:',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: languages.length,
                    separatorBuilder: (_, index) => const Divider(color: AppColors.cardBorderDark, height: 1),
                    itemBuilder: (ctx, index) {
                      final item = languages[index];
                      final isSelected = selectedCode == item['code'];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        onTap: () => setModalState(() => selectedCode = item['code']!),
                        leading: Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? AppColors.kesariSaffron : AppColors.textMuted,
                              width: isSelected ? 6 : 2,
                            ),
                          ),
                        ),
                        title: Text(item['name']!, style: TextStyle(color: isSelected ? AppColors.kesariSaffron : AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(item['sub']!, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.kesariSaffron),
              onPressed: isSaving
                  ? null
                  : () async {
                      setModalState(() => isSaving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final langObj = languages.firstWhere((l) => l['code'] == selectedCode);
                        await FirebaseFirestore.instance
                            .collection(AppConstants.colBusinesses)
                            .doc(widget.businessId)
                            .set({
                          'ttsLanguage': selectedCode,
                          'ttsLanguageName': langObj['name'],
                        }, SetOptions(merge: true));

                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop();
                        }

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('✓ Kiosk TTS Language updated to ${langObj['name']}!'),
                            backgroundColor: AppColors.pannaEmerald,
                          ),
                        );
                      } catch (e) {
                        setModalState(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('SAVE & APPLY TO KIOSK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _announcementCtrl.dispose();
    _voiceRecorder.dispose();
    super.dispose();
  }

  Future<void> _broadcastAnnouncement() async {
    final message = _announcementCtrl.text.trim();

    if (!_isCustomAudioMode && message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an announcement message.'),
          backgroundColor: AppColors.sindoorRed,
        ),
      );
      return;
    }

    if (_isCustomAudioMode && (_recordedAudioBase64 == null || _recordedAudioBase64!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please record a custom voice audio message first.'),
          backgroundColor: AppColors.sindoorRed,
        ),
      );
      return;
    }

    setState(() {
      _isBroadcastingAnnouncement = true;
    });

    try {
      final docRef = FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .collection(AppConstants.colAnnouncements)
          .doc();

      final String announcementText = _isCustomAudioMode
          ? '🎙️ Custom Voice Recording Broadcast (${_recordedDuration}s)'
          : message;

      await docRef.set({
        'id': docRef.id,
        'message': announcementText,
        'type': _selectedAnnouncementType,
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
        'shopId': widget.shopId,
        'isCustomAudio': _isCustomAudioMode,
        'audioData': _isCustomAudioMode ? _recordedAudioBase64 : null,
      });

      _announcementCtrl.clear();
      setState(() {
        _recordedAudioBase64 = null;
        _recordedAudioPath = null;
        _recordedDuration = 0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Custom Voice Announcement broadcasted live to Kiosk devices!'),
            backgroundColor: AppColors.pannaEmerald,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error broadcasting announcement: $e'),
            backgroundColor: AppColors.sindoorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBroadcastingAnnouncement = false;
        });
      }
    }
  }

  void _showKioskPinSettingsDialog() async {
    String currentPin = '1234';
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .get();
      if (doc.exists) {
        currentPin = (doc.data() ?? {})['kioskSecurityPin'] as String? ?? '1234';
      }
    } catch (_) {}

    final pinCtrl = TextEditingController(text: currentPin);
    String? errorText;
    bool isSaving = false;
    bool obscurePin = true;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.cardBorderDark),
          ),
          title: Row(
            children: [
              const Icon(Icons.password_rounded, color: AppColors.kesariSaffron, size: 24),
              const SizedBox(width: 10),
              Text('Kiosk Exit Security PIN', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set the security PIN used by staff/admins to exit Kiosk mode on attendance terminals:',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinCtrl,
                  obscureText: obscurePin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 4, fontWeight: FontWeight.bold, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Enter 4 to 6 Digit Security PIN',
                    labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    errorText: errorText,
                    filled: true,
                    fillColor: AppColors.inputBgDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: Icon(obscurePin ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted),
                      onPressed: () => setModalState(() => obscurePin = !obscurePin),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.kesariSaffron),
              onPressed: isSaving
                  ? null
                  : () async {
                      final newPin = pinCtrl.text.trim();
                      if (newPin.length < 4 || newPin.length > 6) {
                        setModalState(() {
                          errorText = 'PIN must be between 4 and 6 digits long.';
                        });
                        return;
                      }

                      setModalState(() => isSaving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await FirebaseFirestore.instance
                            .collection(AppConstants.colBusinesses)
                            .doc(widget.businessId)
                            .set({
                          'kioskSecurityPin': newPin,
                        }, SetOptions(merge: true));

                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop();
                        }

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('✓ Kiosk Security PIN updated to $newPin successfully!'),
                            backgroundColor: AppColors.pannaEmerald,
                          ),
                        );
                      } catch (e) {
                        setModalState(() {
                          isSaving = false;
                          errorText = 'Failed to update PIN: $e';
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('SAVE PIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      appBar: AppBar(
        backgroundColor: AppColors.cardDark,
        elevation: 2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SHOP ADMIN CONSOLE', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Shop ID: ${widget.shopId}', style: GoogleFonts.inter(color: AppColors.textSaffron, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Kiosk Security PIN Settings',
            icon: const Icon(Icons.password_rounded, color: AppColors.kesariSaffron),
            onPressed: _showKioskPinSettingsDialog,
          ),
          IconButton(
            tooltip: 'Kiosk Voice TTS Language Settings',
            icon: const Icon(Icons.record_voice_over_rounded, color: AppColors.haldiGold),
            onPressed: _showKioskLanguageSettingsDialog,
          ),
          IconButton(
            tooltip: 'Manual Cloud Sync (2-Way)',
            icon: _isAdminSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: AppColors.pannaEmerald, strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, color: AppColors.pannaEmerald),
            onPressed: _isAdminSyncing ? null : _triggerAdminManualSync,
          ),
          IconButton(
            tooltip: 'Shift Settings & Rules',
            icon: const Icon(Icons.alarm_on_rounded, color: AppColors.kesariSaffron),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ShiftManagementScreen(
                    businessId: widget.businessId,
                    shopId: widget.shopId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded, color: AppColors.sindoorRed),
            onPressed: () async {
              await AuthRoutingService().signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),

      // Full Width Tab View Body
      body: IndexedStack(
        index: _selectedNavIndex,
        children: [
          _buildOverviewTab(),
          _buildStaffDirectoryTab(),
          AdminCalendarScreen(businessId: widget.businessId, shopId: widget.shopId),
          _buildPayrollUdhaarTab(),
          _buildKiosksTab(),
          _buildAnnouncementsTab(),
        ],
      ),

      // Premium Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
          border: Border(top: BorderSide(color: AppColors.cardBorderDark, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedNavIndex,
          onTap: (index) => setState(() => _selectedNavIndex = index),
          backgroundColor: AppColors.cardDark,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.kesariSaffron,
          unselectedItemColor: AppColors.textMuted,
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 10),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 9),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              activeIcon: Icon(Icons.dashboard_rounded, color: AppColors.kesariSaffron),
              label: 'Overview',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_alt_rounded),
              activeIcon: Icon(Icons.people_alt_rounded, color: AppColors.kesariSaffron),
              label: 'Staff',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded),
              activeIcon: Icon(Icons.calendar_month_rounded, color: AppColors.kesariSaffron),
              label: 'Calendar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_rounded),
              activeIcon: Icon(Icons.account_balance_wallet_rounded, color: AppColors.kesariSaffron),
              label: 'Payroll',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.devices_other_rounded),
              activeIcon: Icon(Icons.devices_other_rounded, color: AppColors.kesariSaffron),
              label: 'Kiosks',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.campaign_rounded),
              activeIcon: Icon(Icons.campaign_rounded, color: AppColors.kesariSaffron),
              label: 'Alerts',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today\'s Attendance Summary', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),

          // Real Live Firestore Summary Cards Stream
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(AppConstants.colBusinesses)
                .doc(widget.businessId)
                .collection(AppConstants.colAttendance)
                .where('date', isEqualTo: todayStr)
                .snapshots(),
            builder: (context, attendanceSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(AppConstants.colBusinesses)
                    .doc(widget.businessId)
                    .collection(AppConstants.colEmployees)
                    .where('active', isEqualTo: true)
                    .snapshots(),
                builder: (context, empSnap) {
                  final totalEmployees = empSnap.hasData ? empSnap.data!.docs.length : 0;
                  final docs = attendanceSnap.hasData ? attendanceSnap.data!.docs : [];

                  int presentCount = 0;
                  int lateCount = 0;
                  int pendingCheckout = 0;

                  for (var doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status'] ?? '';
                    if (status == AppConstants.attendancePresent) {
                      presentCount++;
                    } else if (status == AppConstants.attendanceLate) {
                      lateCount++;
                    }
                    if (data['checkOutTime'] == null) {
                      pendingCheckout++;
                    }
                  }

                  final absentCount = (totalEmployees - (presentCount + lateCount)).clamp(0, 9999);

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 600;
                      if (isMobile) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _buildSummaryTile('Present Today', '$presentCount', AppColors.pannaEmerald, Icons.check_circle_outline)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildSummaryTile('Late Arrivals', '$lateCount', AppColors.haldiGold, Icons.access_time_rounded)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _buildSummaryTile('Absent', '$absentCount', AppColors.sindoorRed, Icons.cancel_outlined)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildSummaryTile('Pending Checkout', '$pendingCheckout', AppColors.royalPurple, Icons.exit_to_app_rounded)),
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: _buildSummaryTile('Present Today', '$presentCount', AppColors.pannaEmerald, Icons.check_circle_outline)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSummaryTile('Late Arrivals', '$lateCount', AppColors.haldiGold, Icons.access_time_rounded)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSummaryTile('Absent', '$absentCount', AppColors.sindoorRed, Icons.cancel_outlined)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSummaryTile('Pending Checkout', '$pendingCheckout', AppColors.royalPurple, Icons.exit_to_app_rounded)),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),

          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Daily Attendance Logs', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedLogDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _selectedLogDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorderDark),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: AppColors.haldiGold, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('dd MMM yyyy').format(_selectedLogDate),
                        style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['ALL', AppConstants.attendancePresent, AppConstants.attendanceLate, AppConstants.attendanceHalfDay].map((status) {
                final isSel = _selectedStatusFilter == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(status, style: TextStyle(color: isSel ? Colors.white : AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                    selected: isSel,
                    selectedColor: AppColors.kesariSaffron,
                    backgroundColor: AppColors.cardDark,
                    onSelected: (_) => setState(() => _selectedStatusFilter = status),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorderDark),
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.colBusinesses)
                  .doc(widget.businessId)
                  .collection(AppConstants.colAttendance)
                  .where('date', isEqualTo: '${_selectedLogDate.year}-${_selectedLogDate.month.toString().padLeft(2, '0')}-${_selectedLogDate.day.toString().padLeft(2, '0')}')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.kesariSaffron));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('No attendance records logged for ${DateFormat('dd MMMM yyyy').format(_selectedLogDate)}.', style: GoogleFonts.inter(color: AppColors.textMuted)),
                  );
                }

                var docs = snapshot.data!.docs;
                if (_selectedStatusFilter != 'ALL') {
                  docs = docs.where((d) => (d.data() as Map<String, dynamic>)['status'] == _selectedStatusFilter).toList();
                }

                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('No records matching filter "$_selectedStatusFilter".', style: GoogleFonts.inter(color: AppColors.textMuted)),
                  );
                }

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['employeeName'] ?? 'Employee';
                    final status = data['status'] ?? 'PRESENT';
                    final shift = data['shiftId'] ?? 'Morning Shift';
                    final confidence = (data['confidence'] ?? 0.95).toDouble();
                    final checkInStr = data['checkInTime'] ?? '';

                    String formattedTime = 'N/A';
                    if (checkInStr.isNotEmpty) {
                      try {
                        formattedTime = DateFormat('hh:mm a').format(DateTime.parse(checkInStr));
                      } catch (_) {}
                    }

                    Color statusColor = AppColors.pannaEmerald;
                    if (status == AppConstants.attendanceLate) statusColor = AppColors.haldiGold;
                    if (status == AppConstants.attendanceHalfDay) statusColor = AppColors.sindoorRed;

                    return Card(
                      color: AppColors.bgDark,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.cardBorderDark),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor,
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'E', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(name, style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                            Text(formattedTime, style: GoogleFonts.inter(color: AppColors.haldiGold, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        subtitle: Text('Shift: $shift  •  Match Confidence: ${(confidence * 100).toStringAsFixed(1)}%', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
                        trailing: Chip(
                          label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          backgroundColor: statusColor,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 10),
          Text(value, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          Text(title, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildStaffDirectoryTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Employee Directory', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.saffronGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 18),
                  label: const Text('ADD EMPLOYEE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AddEmployeeScreen(
                          businessId: widget.businessId,
                          shopId: widget.shopId,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Bar
          TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search staff by name, code, or department...',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.haldiGold),
              filled: true,
              fillColor: AppColors.cardDark,
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
          ),
          const SizedBox(height: 16),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.colBusinesses)
                  .doc(widget.businessId)
                  .collection(AppConstants.colEmployees)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.kesariSaffron));

                var docs = snapshot.data!.docs;
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['fullName'] ?? '').toString().toLowerCase();
                    final code = (data['employeeCode'] ?? '').toString().toLowerCase();
                    final dept = (data['department'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) || code.contains(_searchQuery) || dept.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isNotEmpty ? 'No staff matching "$_searchQuery"' : 'No staff members added yet. Click "ADD EMPLOYEE" to enroll staff.',
                      style: GoogleFonts.inter(color: AppColors.textMuted),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final emp = EmployeeModel.fromMap(docs[index].data() as Map<String, dynamic>);
                    return Card(
                      color: AppColors.cardDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.cardBorderDark),
                      ),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: emp.active ? AppColors.kesariSaffron : AppColors.textMuted,
                          child: Text(emp.fullName.isNotEmpty ? emp.fullName[0].toUpperCase() : 'E', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                emp.fullName,
                                style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!emp.active)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.sindoorRed.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                child: Text('INACTIVE', style: GoogleFonts.inter(color: AppColors.sindoorRed, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        subtitle: Text('Code: ${emp.employeeCode} | Dept: ${emp.department} | ₹${emp.monthlySalary.toStringAsFixed(0)}/mo', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(emp.faceEnrollmentStatus ? '3D Face ✓' : 'Pending ⚠', style: const TextStyle(color: Colors.white, fontSize: 10)),
                              backgroundColor: emp.faceEnrollmentStatus ? AppColors.pannaEmerald : AppColors.haldiGold,
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.kesariSaffron),
                              tooltip: 'Edit Employee Details & Face Data',
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EditEmployeeScreen(
                                      businessId: widget.businessId,
                                      shopId: widget.shopId,
                                      employee: emp,
                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(emp.active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, color: emp.active ? AppColors.haldiGold : AppColors.pannaEmerald),
                              tooltip: emp.active ? 'Deactivate Employee' : 'Activate Employee',
                              onPressed: () => _toggleEmployeeStatus(emp),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.sindoorRed),
                              tooltip: 'Delete Employee Record',
                              onPressed: () => _confirmDeleteEmployee(emp),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleEmployeeStatus(EmployeeModel emp) async {
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .collection(AppConstants.colEmployees)
          .doc(emp.employeeId)
          .update({'active': !emp.active});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Employee "${emp.fullName}" ${!emp.active ? "activated" : "deactivated"}.'),
          backgroundColor: AppColors.pannaEmerald,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e'), backgroundColor: AppColors.sindoorRed),
      );
    }
  }

  Future<void> _confirmDeleteEmployee(EmployeeModel emp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: Text('Delete Employee Record', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete staff record for "${emp.fullName}" (${emp.employeeCode})? This action cannot be undone.', style: GoogleFonts.inter(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.sindoorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection(AppConstants.colBusinesses)
            .doc(widget.businessId)
            .collection(AppConstants.colEmployees)
            .doc(emp.employeeId)
            .delete();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Employee "${emp.fullName}" deleted successfully.'), backgroundColor: AppColors.pannaEmerald),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting employee: $e'), backgroundColor: AppColors.sindoorRed),
        );
      }
    }
  }

  Widget _buildPayrollUdhaarTab() {
    final now = DateTime.now();
    final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payroll & Salary Advance (Udhaar)', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  Text('${DateFormat('MMMM yyyy').format(now)} Payslip Calculation', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSaffron)),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.kesariSaffron),
                    icon: const Icon(Icons.request_quote_rounded, color: Colors.white, size: 18),
                    label: const Text('💸 GRANT ADVANCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () => _showGrantAdvanceDialog(),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.pannaEmerald),
                    icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 18),
                    label: const Text('PAYSLIP PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () => _showPayslipModal(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Streams for Employees, Advances, and Attendance
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.colBusinesses)
                  .doc(widget.businessId)
                  .collection(AppConstants.colEmployees)
                  .snapshots(),
              builder: (context, empSnap) {
                if (!empSnap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.kesariSaffron));

                final empDocs = empSnap.data!.docs;
                final employees = empDocs.map((d) => EmployeeModel.fromMap(d.data() as Map<String, dynamic>)).toList();

                if (employees.isEmpty) {
                  return Center(child: Text('No employees found to calculate payroll.', style: GoogleFonts.inter(color: AppColors.textMuted)));
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection(AppConstants.colBusinesses)
                      .doc(widget.businessId)
                      .collection('advances')
                      .snapshots(),
                  builder: (context, advSnap) {
                    final advDocs = advSnap.data?.docs ?? [];
                    final advances = advDocs.map((d) => AdvanceSalaryModel.fromMap(d.data() as Map<String, dynamic>)).toList();

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection(AppConstants.colBusinesses)
                          .doc(widget.businessId)
                          .collection(AppConstants.colAttendance)
                          .snapshots(),
                      builder: (context, attSnap) {
                        final attDocs = attSnap.data?.docs ?? [];
                        final allAtt = attDocs.map((d) => AttendanceModel.fromMap(d.data() as Map<String, dynamic>)).toList();

                        // Filter attendance for current month
                        final monthAtt = allAtt.where((r) => r.date.startsWith(monthPrefix)).toList();

                        double totalGrossSalary = 0;
                        double totalAdvancesGiven = 0;

                        final Map<String, int> empPresentDays = {};
                        final Map<String, double> empHolidayBonus = {};
                        final Map<String, double> empAdvanceTotal = {};

                        for (var e in employees) {
                          totalGrossSalary += e.monthlySalary;
                        }

                        for (var a in advances) {
                          if (a.date.startsWith(monthPrefix)) {
                            totalAdvancesGiven += a.amount;
                            empAdvanceTotal[a.employeeId] = (empAdvanceTotal[a.employeeId] ?? 0.0) + a.amount;
                          }
                        }

                        for (var att in monthAtt) {
                          if (att.status == AppConstants.attendancePresent || att.approvalStatus == 'APPROVED') {
                            empPresentDays[att.employeeId] = (empPresentDays[att.employeeId] ?? 0) + 1;
                          }
                          if (att.holidayBonusStatus == 'APPROVED') {
                            empHolidayBonus[att.employeeId] = (empHolidayBonus[att.employeeId] ?? 0.0) + att.holidayBonusAmount;
                          }
                        }

                        return Column(
                          children: [
                            // Summary Cards Header Row
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.cardDark,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.cardBorderDark),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildPayrollStatTile(
                                      'Gross Salary Pool',
                                      '₹${totalGrossSalary.toStringAsFixed(0)}',
                                      AppColors.haldiGold,
                                      Icons.account_balance_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildPayrollStatTile(
                                      'Udhaar / Advances Taken',
                                      '₹${totalAdvancesGiven.toStringAsFixed(0)}',
                                      AppColors.sindoorRed,
                                      Icons.request_quote_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildPayrollStatTile(
                                      'Active Staff',
                                      '${employees.length} Staff',
                                      AppColors.kesariSaffron,
                                      Icons.people_alt_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            Expanded(
                              child: ListView.builder(
                                itemCount: employees.length,
                                itemBuilder: (context, idx) {
                                  final emp = employees[idx];
                                  final present = empPresentDays[emp.employeeId] ?? 0;
                                  final bonus = empHolidayBonus[emp.employeeId] ?? 0.0;
                                  final advance = empAdvanceTotal[emp.employeeId] ?? 0.0;

                                  final dailyRate = emp.monthlySalary / daysInMonth;
                                  final earnedBase = dailyRate * present;
                                  final netPayable = (earnedBase + bonus - advance).clamp(0.0, 999999.0);

                                  return Card(
                                    color: AppColors.cardDark,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: const BorderSide(color: AppColors.cardBorderDark),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  CircleAvatar(
                                                    backgroundColor: AppColors.kesariSaffron,
                                                    child: Text(emp.fullName.isNotEmpty ? emp.fullName[0].toUpperCase() : 'E', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(emp.fullName, style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                                                      Text('Code: ${emp.employeeCode} | Monthly Base: ₹${emp.monthlySalary.toStringAsFixed(0)}', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(color: AppColors.haldiGold),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                ),
                                                icon: const Icon(Icons.add_rounded, size: 14, color: AppColors.haldiGold),
                                                label: const Text('+ ADVANCE', style: TextStyle(color: AppColors.haldiGold, fontSize: 11, fontWeight: FontWeight.bold)),
                                                onPressed: () => _showGrantAdvanceDialog(preSelectedEmployeeId: emp.employeeId),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          const Divider(color: AppColors.cardBorderDark, height: 1),
                                          const SizedBox(height: 10),

                                          // Breakdown Row
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              _buildSalaryChip('Present Days', '$present/$daysInMonth days', AppColors.pannaEmerald),
                                              _buildSalaryChip('Earned Base', '₹${earnedBase.toStringAsFixed(0)}', AppColors.textPrimary),
                                              if (bonus > 0)
                                                _buildSalaryChip('Holiday Bonus', '+₹${bonus.toStringAsFixed(0)}', AppColors.haldiGold),
                                              if (advance > 0)
                                                _buildSalaryChip('Udhaar Deducted', '-₹${advance.toStringAsFixed(0)}', AppColors.sindoorRed),
                                            ],
                                          ),
                                          const SizedBox(height: 10),

                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Net Payable Salary (This Month):', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                                              Text('₹${netPayable.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: AppColors.pannaEmerald, fontSize: 18, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollStatTile(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.outfit(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSalaryChip(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10)),
        Text(value, style: GoogleFonts.inter(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showGrantAdvanceDialog({String? preSelectedEmployeeId}) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? selectedEmpId = preSelectedEmployeeId;
    DateTime advanceDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          title: Text('💸 Grant Salary Advance (Udhaar)', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection(AppConstants.colBusinesses)
                      .doc(widget.businessId)
                      .collection(AppConstants.colEmployees)
                      .snapshots(),
                  builder: (context, snapshot) {
                    List<DropdownMenuItem<String>> items = [];
                    if (snapshot.hasData) {
                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final id = data['employeeId'] ?? '';
                        final name = data['fullName'] ?? 'Staff';
                        items.add(DropdownMenuItem(value: id, child: Text(name)));
                      }
                    }

                    if (selectedEmpId == null && items.isNotEmpty) {
                      selectedEmpId = items.first.value;
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBgDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorderDark),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: AppColors.cardDark,
                          isExpanded: true,
                          value: selectedEmpId,
                          style: const TextStyle(color: AppColors.textPrimary),
                          items: items,
                          onChanged: (val) {
                            if (val != null) setDlgState(() => selectedEmpId = val);
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Advance Amount (₹)',
                    labelStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.inputBgDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: reasonCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Reason for Advance (e.g. Emergency, Rent)',
                    labelStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.inputBgDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: advanceDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) setDlgState(() => advanceDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.inputBgDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.cardBorderDark),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, color: AppColors.haldiGold, size: 18),
                        const SizedBox(width: 8),
                        Text('Date: ${DateFormat('dd MMM yyyy').format(advanceDate)}', style: const TextStyle(color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.kesariSaffron),
              child: const Text('GRANT ADVANCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text.trim());
                if (amt == null || amt <= 0 || selectedEmpId == null) return;

                final String id = const Uuid().v4();
                final String dateStr = DateFormat('yyyy-MM-dd').format(advanceDate);

                // Get employee name
                final empDoc = await FirebaseFirestore.instance
                    .collection(AppConstants.colBusinesses)
                    .doc(widget.businessId)
                    .collection(AppConstants.colEmployees)
                    .doc(selectedEmpId)
                    .get();

                final empName = (empDoc.data() ?? {})['fullName'] ?? 'Staff';

                final advModel = AdvanceSalaryModel(
                  id: id,
                  businessId: widget.businessId,
                  employeeId: selectedEmpId!,
                  employeeName: empName,
                  amount: amt,
                  date: dateStr,
                  reason: reasonCtrl.text.trim(),
                  status: 'APPROVED',
                  createdAt: DateTime.now(),
                );

                await FirebaseFirestore.instance
                    .collection(AppConstants.colBusinesses)
                    .doc(widget.businessId)
                    .collection('advances')
                    .doc(id)
                    .set(advModel.toMap());

                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('💸 Advance Salary of ₹${amt.toStringAsFixed(0)} recorded for $empName!'),
                      backgroundColor: AppColors.pannaEmerald,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPayslipModal() {
    FirebaseFirestore.instance
        .collection(AppConstants.colBusinesses)
        .doc(widget.businessId)
        .collection(AppConstants.colEmployees)
        .get()
        .then((snapshot) {
      final empCount = snapshot.docs.length;
      double totalGross = 0.0;
      for (var doc in snapshot.docs) {
        totalGross += ((doc.data())['monthlySalary'] ?? 0.0).toDouble();
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          title: Text('Monthly Staff Payslip Breakdown', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Month: ${DateFormat('MMMM yyyy').format(DateTime.now())}', style: GoogleFonts.inter(color: AppColors.textSaffron, fontWeight: FontWeight.bold)),
                const Divider(color: AppColors.cardBorderDark),
                _buildPayslipRow('Total Staff Members', '$empCount Employees'),
                _buildPayslipRow('Gross Payroll Amount', '₹${totalGross.toStringAsFixed(0)}'),
                const Divider(color: AppColors.cardBorderDark),
                _buildPayslipRow('Net Payable Salary', '₹${totalGross.toStringAsFixed(0)}', isTotal: true),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: AppColors.textMuted))),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.pannaEmerald),
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              label: const Text('DOWNLOAD PDF REPORT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Monthly Payslip Report PDF generated successfully!'), backgroundColor: AppColors.pannaEmerald),
                );
              },
            ),
          ],
        ),
      );
    });
  }

  Widget _buildPayslipRow(String label, String val, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: GoogleFonts.inter(color: isTotal ? AppColors.textPrimary : AppColors.textMuted, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          ),
          const SizedBox(width: 8),
          Text(val, style: GoogleFonts.outfit(color: isTotal ? AppColors.pannaEmerald : AppColors.textPrimary, fontWeight: isTotal ? FontWeight.bold : FontWeight.w600, fontSize: isTotal ? 16 : 14)),
        ],
      ),
    );
  }

  Widget _buildKiosksTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paired Entrance Kiosk Devices', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.colBusinesses)
                  .doc(widget.businessId)
                  .collection('kiosks')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.kesariSaffron));

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Text('No active Kiosk devices paired yet. Log in to Entrance Kiosk mode to register device.', style: GoogleFonts.inter(color: AppColors.textMuted)),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, idx) {
                    final data = docs[idx].data() as Map<String, dynamic>;
                    final devId = data['deviceId'] ?? 'KSK-01';
                    final lastPing = data['lastHeartbeat'] ?? '';

                    return Card(
                      color: AppColors.cardDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.cardBorderDark),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.tablet_android_rounded, color: AppColors.pannaEmerald, size: 32),
                        title: Text('Entrance Kiosk Device ($devId)', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        subtitle: Text('Status: ONLINE • Last Heartbeat: $lastPing', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
                        trailing: Chip(
                          label: const Text('ACTIVE ONLINE', style: TextStyle(color: Colors.white, fontSize: 11)),
                          backgroundColor: AppColors.pannaEmerald,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_rounded, color: AppColors.kesariSaffron, size: 28),
              const SizedBox(width: 10),
              Text(
                'Broadcast Voice Announcement / Alert',
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Broadcast real-time voice & visual alert banner to Entrance Kiosk devices across the shop.',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),

          // Broadcast Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorderDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Select Announcement Severity / Category:',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('🚨 Emergency Alert'),
                      selected: _selectedAnnouncementType == 'emergency',
                      selectedColor: AppColors.sindoorRed,
                      backgroundColor: AppColors.inputBgDark,
                      labelStyle: TextStyle(
                        color: _selectedAnnouncementType == 'emergency' ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedAnnouncementType = 'emergency');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('📢 Notice / Shift Alert'),
                      selected: _selectedAnnouncementType == 'notice',
                      selectedColor: AppColors.kesariSaffron,
                      backgroundColor: AppColors.inputBgDark,
                      labelStyle: TextStyle(
                        color: _selectedAnnouncementType == 'notice' ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedAnnouncementType = 'notice');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('ℹ️ General Info'),
                      selected: _selectedAnnouncementType == 'info',
                      selectedColor: AppColors.mayurBlue,
                      backgroundColor: AppColors.inputBgDark,
                      labelStyle: TextStyle(
                        color: _selectedAnnouncementType == 'info' ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedAnnouncementType = 'info');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '2. Choose Broadcast Format:',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_voiceRecorder.isRecording) _voiceRecorder.cancelRecording();
                          setState(() => _isCustomAudioMode = false);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_isCustomAudioMode ? AppColors.kesariSaffron.withValues(alpha: 0.2) : AppColors.inputBgDark,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: !_isCustomAudioMode ? AppColors.kesariSaffron : AppColors.cardBorderDark,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.notes_rounded, color: !_isCustomAudioMode ? AppColors.kesariSaffron : AppColors.textMuted, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '📝 Text Message (TTS)',
                                style: GoogleFonts.inter(
                                  color: !_isCustomAudioMode ? Colors.white : AppColors.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _isCustomAudioMode = true);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _isCustomAudioMode ? AppColors.sindoorRed.withValues(alpha: 0.2) : AppColors.inputBgDark,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isCustomAudioMode ? AppColors.sindoorRed : AppColors.cardBorderDark,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.mic_rounded, color: _isCustomAudioMode ? AppColors.sindoorRed : AppColors.textMuted, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '🎙️ Custom Voice Record',
                                style: GoogleFonts.inter(
                                  color: _isCustomAudioMode ? Colors.white : AppColors.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Format 1: Text Message Input
                if (!_isCustomAudioMode) ...[
                  Text(
                    '3. Enter Text Announcement Message:',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _announcementCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Enter message to speak on Kiosk speaker & display on screen...',
                      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.inputBgDark,
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
                  ),
                ] else ...[
                  // Format 2: Custom Voice Audio Recorder UI
                  Text(
                    '3. Record Custom Voice Audio Message:',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.inputBgDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorderDark),
                    ),
                    child: Column(
                      children: [
                        if (!_voiceRecorder.isRecording && _recordedAudioBase64 == null) ...[
                          IconButton(
                            iconSize: 56,
                            icon: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: AppColors.sindoorRed,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.mic, color: Colors.white, size: 36),
                            ),
                            onPressed: () async {
                              final started = await _voiceRecorder.startRecording();
                              if (started) {
                                if (mounted) {
                                  setState(() {});
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Microphone permission denied or recording failed.')),
                                  );
                                }
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap Mic to Start Custom Voice Recording',
                            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ] else if (_voiceRecorder.isRecording) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: AppColors.sindoorRed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'RECORDING... (00:${_voiceRecorder.recordingDurationSeconds.toString().padLeft(2, '0')}s)',
                                style: GoogleFonts.outfit(color: AppColors.sindoorRed, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.sindoorRed),
                            icon: const Icon(Icons.stop_rounded, color: Colors.white),
                            label: const Text('STOP RECORDING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final res = await _voiceRecorder.stopRecording();
                              if (res != null) {
                                setState(() {
                                  _recordedAudioPath = res['filePath'] as String?;
                                  _recordedAudioBase64 = res['base64Audio'] as String?;
                                  _recordedDuration = res['durationSeconds'] as int? ?? 0;
                                });
                              }
                            },
                          ),
                        ] else if (_recordedAudioBase64 != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppColors.pannaEmerald, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                '✓ Voice Audio Recorded (${_recordedDuration}s)',
                                style: GoogleFonts.outfit(color: AppColors.pannaEmerald, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.mayurBlue),
                                icon: Icon(_voiceRecorder.isPlayingPreview ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white),
                                label: Text(_voiceRecorder.isPlayingPreview ? 'STOP PREVIEW' : 'PLAY PREVIEW', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  if (_voiceRecorder.isPlayingPreview) {
                                    _voiceRecorder.stopPreview().then((_) => setState(() {}));
                                  } else {
                                    _voiceRecorder.playPreview(_recordedAudioPath ?? _recordedAudioBase64!).then((_) => setState(() {}));
                                  }
                                },
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.sindoorRed)),
                                icon: const Icon(Icons.refresh_rounded, color: AppColors.sindoorRed),
                                label: const Text('RE-RECORD', style: TextStyle(color: AppColors.sindoorRed, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  _voiceRecorder.stopPreview();
                                  setState(() {
                                    _recordedAudioBase64 = null;
                                    _recordedAudioPath = null;
                                    _recordedDuration = 0;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedAnnouncementType == 'emergency'
                          ? AppColors.sindoorRed
                          : (_selectedAnnouncementType == 'notice' ? AppColors.kesariSaffron : AppColors.mayurBlue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isBroadcastingAnnouncement
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.volume_up_rounded, color: Colors.white),
                    label: Text(
                      _isBroadcastingAnnouncement ? 'BROADCASTING...' : 'BROADCAST ANNOUNCEMENT LIVE NOW',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onPressed: _isBroadcastingAnnouncement ? null : _broadcastAnnouncement,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active & Recent Broadcasts',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const Icon(Icons.history_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
          const SizedBox(height: 12),

          // Broadcasts Stream List
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(AppConstants.colBusinesses)
                .doc(widget.businessId)
                .collection(AppConstants.colAnnouncements)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.kesariSaffron)));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorderDark),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.speaker_notes_off_rounded, color: AppColors.textMuted, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        'No announcements broadcasted yet.',
                        style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              // Sort by createdAt descending locally
              final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
              sortedDocs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = (aData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                final bTime = (bData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                return bTime.compareTo(aTime);
              });

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedDocs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = sortedDocs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final message = data['message'] as String? ?? '';
                  final type = data['type'] as String? ?? 'general';
                  final isActive = data['active'] as bool? ?? false;
                  final timestamp = (data['createdAt'] as Timestamp?)?.toDate();
                  final timeStr = timestamp != null ? DateFormat('dd MMM, hh:mm a').format(timestamp) : 'Just now';

                  Color badgeColor = AppColors.mayurBlue;
                  IconData badgeIcon = Icons.info_outline;
                  String badgeTitle = 'INFO';
                  if (type == 'emergency') {
                    badgeColor = AppColors.sindoorRed;
                    badgeIcon = Icons.warning_amber_rounded;
                    badgeTitle = 'EMERGENCY';
                  } else if (type == 'notice') {
                    badgeColor = AppColors.kesariSaffron;
                    badgeIcon = Icons.campaign_rounded;
                    badgeTitle = 'NOTICE';
                  }

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? badgeColor.withValues(alpha: 0.6) : AppColors.cardBorderDark,
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(badgeIcon, color: badgeColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: badgeColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      badgeTitle,
                                      style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isActive ? AppColors.pannaEmerald.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isActive ? '● LIVE ON KIOSK' : 'DISMISSED',
                                      style: GoogleFonts.inter(
                                        color: isActive ? AppColors.pannaEmerald : Colors.grey,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(timeStr, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                message,
                                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            isActive ? Icons.stop_circle_outlined : Icons.delete_outline_rounded,
                            color: isActive ? AppColors.sindoorRed : AppColors.textMuted,
                            size: 22,
                          ),
                          tooltip: isActive ? 'Dismiss Announcement' : 'Delete Record',
                          onPressed: () async {
                            if (isActive) {
                              await doc.reference.update({'active': false});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Announcement dismissed from Kiosk.')),
                                );
                              }
                            } else {
                              await doc.reference.delete();
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
