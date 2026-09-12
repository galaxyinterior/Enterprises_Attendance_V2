import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/offline_db_service.dart';
import '../../models/attendance_model.dart';
import '../../models/holiday_model.dart';

class AdminCalendarScreen extends StatefulWidget {
  final String businessId;
  final String shopId;

  const AdminCalendarScreen({
    super.key,
    required this.businessId,
    required this.shopId,
  });

  @override
  State<AdminCalendarScreen> createState() => _AdminCalendarScreenState();
}

class _AdminCalendarScreenState extends State<AdminCalendarScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String? _selectedEmployeeId; // null = All Employees
  final _offlineDb = OfflineDbService();

  void _changeMonth(int increment) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + increment, 1);
    });
  }

  Future<void> _updateApproval(AttendanceModel att, bool approve) async {
    final String newApprovalStatus = approve ? 'APPROVED' : 'REJECTED';
    final String newStatus = approve ? AppConstants.attendancePresent : AppConstants.attendanceAbsent;

    try {
      // 1. Update Cloud Firestore
      await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .collection(AppConstants.colAttendance)
          .doc(att.attendanceId)
          .update({
        'approvalStatus': newApprovalStatus,
        'status': newStatus,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // 2. Update local SQLite DB
      await _offlineDb.updateAttendanceApproval(att.attendanceId, newApprovalStatus, newStatus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? '✓ Late attendance APPROVED! Marked as Present.' : '❌ Late attendance REJECTED! Kept as Absent.'),
            backgroundColor: approve ? AppColors.pannaEmerald : AppColors.sindoorRed,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating approval status: $e');
    }
  }

  Future<void> _updateHolidayBonus(AttendanceModel att, bool approve, double bonusAmount) async {
    final String newBonusStatus = approve ? 'APPROVED' : 'REJECTED';

    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.colBusinesses)
          .doc(widget.businessId)
          .collection(AppConstants.colAttendance)
          .doc(att.attendanceId)
          .update({
        'holidayBonusStatus': newBonusStatus,
        'holidayBonusAmount': approve ? bonusAmount : 0.0,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve
                ? '🎉 Holiday Extra Bonus ₹${bonusAmount.toStringAsFixed(0)} APPROVED for ${att.employeeName}!'
                : '❌ Holiday Bonus REJECTED for ${att.employeeName}.'),
            backgroundColor: approve ? AppColors.pannaEmerald : AppColors.sindoorRed,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating holiday bonus: $e');
    }
  }

  void _showAddHolidayDialog() {
    final titleCtrl = TextEditingController();
    DateTime pickedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          title: Text('🎉 Add Shop Holiday', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Holiday Title (e.g. Diwali, Holi, Sunday Off)',
                  labelStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.inputBgDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: pickedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (d != null) {
                    setDlgState(() => pickedDate = d);
                  }
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
                      const Icon(Icons.calendar_month_rounded, color: AppColors.kesariSaffron, size: 18),
                      const SizedBox(width: 8),
                      Text(DateFormat('dd MMMM yyyy (EEEE)').format(pickedDate), style: const TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.kesariSaffron),
              child: const Text('ADD HOLIDAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;

                final dateStr = DateFormat('yyyy-MM-dd').format(pickedDate);
                final id = const Uuid().v4();

                final holiday = HolidayModel(
                  id: id,
                  businessId: widget.businessId,
                  date: dateStr,
                  title: title,
                  createdAt: DateTime.now(),
                );

                await FirebaseFirestore.instance
                    .collection(AppConstants.colBusinesses)
                    .doc(widget.businessId)
                    .collection('holidays')
                    .doc(id)
                    .set(holiday.toMap());

                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String monthYearStr = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month Navigation & Filters Header
            _buildHeaderFilterCard(monthYearStr),
            const SizedBox(height: 16),

            // Realtime Stream of Holidays & Attendance
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.colBusinesses)
                  .doc(widget.businessId)
                  .collection('holidays')
                  .snapshots(),
              builder: (context, holidaySnapshot) {
                final holidayDocs = holidaySnapshot.data?.docs ?? [];
                final List<HolidayModel> holidays = holidayDocs
                    .map((d) => HolidayModel.fromMap(d.data() as Map<String, dynamic>))
                    .toList();

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection(AppConstants.colBusinesses)
                      .doc(widget.businessId)
                      .collection(AppConstants.colAttendance)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(color: AppColors.kesariSaffron)));
                    }

                    final docs = snapshot.data?.docs ?? [];
                    List<AttendanceModel> allRecords = docs.map((d) => AttendanceModel.fromMap(d.data() as Map<String, dynamic>)).toList();

                    // Filter by month (YYYY-MM)
                    final monthPrefix = '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';
                    List<AttendanceModel> monthRecords = allRecords.where((r) => r.date.startsWith(monthPrefix)).toList();

                    // Filter by selected employee if specified
                    if (_selectedEmployeeId != null && _selectedEmployeeId!.isNotEmpty) {
                      monthRecords = monthRecords.where((r) => r.employeeId == _selectedEmployeeId).toList();
                    }

                    // Calculate summary counters
                    int presentCount = 0;
                    int absentCount = 0;
                    int lateCount = 0;
                    int pendingCount = 0;

                    for (var r in monthRecords) {
                      if (r.approvalStatus == 'PENDING') {
                        pendingCount++;
                        absentCount++; // Pending is counted as Absent until approved!
                        lateCount++;
                      } else if (r.status == AppConstants.attendancePresent || r.approvalStatus == 'APPROVED') {
                        presentCount++;
                        if (r.lateMinutes != null && r.lateMinutes! > 0) lateCount++;
                      } else {
                        absentCount++;
                      }
                    }

                    final pendingLate = monthRecords.where((r) => r.approvalStatus == 'PENDING').toList();
                    final pendingHolidayBonus = monthRecords.where((r) => r.isHolidayWork && r.holidayBonusStatus == 'PENDING').toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Summary Cards Row
                        _buildSummaryCardsRow(
                          present: presentCount,
                          absent: absentCount,
                          late: lateCount,
                          pending: pendingCount,
                        ),
                        const SizedBox(height: 16),

                        // Calendar Sheet Grid
                        _buildCalendarGrid(monthRecords, holidays),
                        const SizedBox(height: 24),

                        // Holiday Work Bonus Approvals Section
                        if (pendingHolidayBonus.isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.stars_rounded, color: AppColors.haldiGold, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                '🎉 Holiday Work Bonus Approvals (${pendingHolidayBonus.length})',
                                style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildPendingHolidayBonusList(pendingHolidayBonus),
                          const SizedBox(height: 24),
                        ],

                        // Pending Approvals Section Header
                        Text(
                          'Pending Late Attendance Approvals (${pendingLate.length})',
                          style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),

                        _buildPendingApprovalsList(pendingLate),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderFilterCard(String monthYearStr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderDark),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.kesariSaffron, size: 18),
                onPressed: () => _changeMonth(-1),
              ),
              Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: AppColors.kesariSaffron, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    monthYearStr,
                    style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.kesariSaffron, size: 18),
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              // Employee Dropdown Stream
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection(AppConstants.colBusinesses)
                      .doc(widget.businessId)
                      .collection(AppConstants.colEmployees)
                      .snapshots(),
                  builder: (context, snapshot) {
                    List<DropdownMenuItem<String>> items = [
                      const DropdownMenuItem(value: '', child: Text('All Employees Report')),
                    ];

                    if (snapshot.hasData) {
                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final id = data['employeeId'] ?? '';
                        final name = data['fullName'] ?? 'Staff';
                        final code = data['employeeCode'] ?? '';
                        items.add(DropdownMenuItem(value: id, child: Text('$name ($code)')));
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.inputBgDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorderDark),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: AppColors.cardDark,
                          isExpanded: true,
                          value: _selectedEmployeeId ?? '',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          items: items,
                          onChanged: (val) {
                            setState(() {
                              _selectedEmployeeId = (val == null || val.isEmpty) ? null : val;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.kesariSaffron,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 18),
                label: const Text('🎉 ADD HOLIDAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: _showAddHolidayDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCardsRow({required int present, required int absent, required int late, required int pending}) {
    return Row(
      children: [
        _buildStatTile('PRESENT', present.toString(), AppColors.pannaEmerald, Icons.check_circle_rounded),
        const SizedBox(width: 8),
        _buildStatTile('ABSENT', absent.toString(), AppColors.sindoorRed, Icons.cancel_rounded),
        const SizedBox(width: 8),
        _buildStatTile('LATE', late.toString(), AppColors.haldiGold, Icons.access_time_filled_rounded),
        const SizedBox(width: 8),
        _buildStatTile('PENDING', pending.toString(), AppColors.kesariSaffron, Icons.hourglass_top_rounded),
      ],
    );
  }

  Widget _buildStatTile(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.outfit(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(List<AttendanceModel> records, List<HolidayModel> holidays) {
    final int daysInMonth = DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month);
    final firstDayOfWeek = DateTime(_selectedMonth.year, _selectedMonth.month, 1).weekday; // 1 = Mon, 7 = Sun

    // Build map date string -> list of records
    final Map<String, List<AttendanceModel>> dayMap = {};
    for (var r in records) {
      dayMap.putIfAbsent(r.date, () => []).add(r);
    }

    // Build map date string -> holiday title
    final Map<String, String> holidayMap = {};
    for (var h in holidays) {
      holidayMap[h.date] = h.title;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderDark),
      ),
      child: Column(
        children: [
          // Days of week header
          Row(
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) {
              return Expanded(
                child: Center(
                  child: Text(d, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.cardBorderDark, height: 1),
          const SizedBox(height: 8),

          // Calendar Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: (daysInMonth + (firstDayOfWeek - 1)),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              if (index < (firstDayOfWeek - 1)) {
                return const SizedBox(); // Empty padding tile
              }

              final dayNum = index - (firstDayOfWeek - 2);
              final dateStr = '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';
              final dayRecords = dayMap[dateStr] ?? [];
              final holidayTitle = holidayMap[dateStr];
              final isHoliday = holidayTitle != null;

              Color bg = isHoliday ? AppColors.haldiGold.withValues(alpha: 0.15) : AppColors.inputBgDark;
              Color border = isHoliday ? AppColors.haldiGold : AppColors.cardBorderDark;
              String statusDot = isHoliday ? '🎉' : '';

              if (dayRecords.isNotEmpty) {
                final hasPending = dayRecords.any((r) => r.approvalStatus == 'PENDING');
                final hasApproved = dayRecords.any((r) => r.approvalStatus == 'APPROVED');
                final hasPresent = dayRecords.any((r) => r.status == AppConstants.attendancePresent);

                if (hasPending) {
                  bg = AppColors.kesariSaffron.withValues(alpha: 0.2);
                  border = AppColors.kesariSaffron;
                  statusDot = '⏳';
                } else if (hasApproved || hasPresent) {
                  bg = AppColors.pannaEmerald.withValues(alpha: 0.2);
                  border = AppColors.pannaEmerald;
                  statusDot = isHoliday ? '🎉✓' : '✓';
                } else {
                  bg = AppColors.sindoorRed.withValues(alpha: 0.2);
                  border = AppColors.sindoorRed;
                  statusDot = '✕';
                }
              }

              return InkWell(
                onTap: (dayRecords.isEmpty && !isHoliday) ? null : () => _showDayDetailDialog(dateStr, dayRecords, holidayTitle),
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(dayNum.toString(), style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      if (statusDot.isNotEmpty)
                        Text(statusDot, style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDayDetailDialog(String dateStr, List<AttendanceModel> records, String? holidayTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Attendance Log: $dateStr', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            if (holidayTitle != null)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.haldiGold.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                child: Text('🎉 Shop Holiday: $holidayTitle', style: GoogleFonts.inter(color: AppColors.haldiGold, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: records.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No attendance recorded on this day.', style: TextStyle(color: AppColors.textMuted)),
                    )
                  ]
                : records.map((r) {
                    return ListTile(
                      title: Text(r.employeeName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Check-In: ${r.checkInTime != null ? DateFormat('hh:mm a').format(r.checkInTime!) : "N/A"}'
                        '${r.isHolidayWork ? "\n⭐ Worked on Holiday" : ""}'
                        '${r.lateReason != null ? "\nReason: ${r.lateReason}" : ""}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: Chip(
                        label: Text(r.status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        backgroundColor: r.status == AppConstants.attendancePresent ? AppColors.pannaEmerald : AppColors.sindoorRed,
                      ),
                    );
                  }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
        ],
      ),
    );
  }

  Widget _buildPendingHolidayBonusList(List<AttendanceModel> list) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final att = list[index];
        final bonusCtrl = TextEditingController(text: '500');

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.haldiGold.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.celebration_rounded, color: AppColors.haldiGold, size: 20),
                      const SizedBox(width: 8),
                      Text(att.employeeName, style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.haldiGold.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                    child: Text('Holiday Work', style: GoogleFonts.inter(color: AppColors.haldiGold, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Date: ${att.date}  |  Attended on Shop Holiday!', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bonusCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Extra Bonus Amount (₹)',
                        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        filled: true,
                        fillColor: AppColors.inputBgDark,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.pannaEmerald,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                    label: const Text('APPROVE BONUS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: () {
                      final b = double.tryParse(bonusCtrl.text.trim()) ?? 500.0;
                      _updateHolidayBonus(att, true, b);
                    },
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.sindoorRed),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('NO BONUS', style: TextStyle(color: AppColors.sindoorRed, fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: () => _updateHolidayBonus(att, false, 0.0),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingApprovalsList(List<AttendanceModel> pendingList) {
    if (pendingList.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorderDark),
        ),
        child: Column(
          children: [
            const Icon(Icons.verified_user_rounded, color: AppColors.pannaEmerald, size: 36),
            const SizedBox(height: 6),
            Text('No Pending Late Approvals', style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            Text('All late arrivals have been reviewed by Admin.', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pendingList.length,
      itemBuilder: (context, index) {
        final att = pendingList[index];
        final checkInStr = att.checkInTime != null ? DateFormat('hh:mm a').format(att.checkInTime!) : 'N/A';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.kesariSaffron.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_pin_rounded, color: AppColors.kesariSaffron, size: 20),
                      const SizedBox(width: 8),
                      Text(att.employeeName, style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.kesariSaffron.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                    child: Text('Late by ${att.lateMinutes ?? 0}m', style: GoogleFonts.inter(color: AppColors.kesariSaffron, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Date: ${att.date}  |  Check-In Time: $checkInStr', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 8),

              // Late Reason Box
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.inputBgDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorderDark),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.format_quote_rounded, color: AppColors.haldiGold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reason: ${att.lateReason ?? "No reason specified"}',
                        style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Action Buttons Row (APPROVE vs REJECT)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.pannaEmerald,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      label: const Text('APPROVE (PRESENT)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => _updateApproval(att, true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.sindoorRed),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.cancel_rounded, color: AppColors.sindoorRed, size: 18),
                      label: const Text('REJECT (ABSENT)', style: TextStyle(color: AppColors.sindoorRed, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => _updateApproval(att, false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

