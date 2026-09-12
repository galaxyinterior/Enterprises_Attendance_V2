import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/offline_db_service.dart';
import '../../models/shift_model.dart';

class ShiftManagementScreen extends StatefulWidget {
  final String businessId;
  final String shopId;

  const ShiftManagementScreen({
    super.key,
    required this.businessId,
    required this.shopId,
  });

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  final _offlineDb = OfflineDbService();

  Future<void> _showAddEditShiftDialog({ShiftModel? existingShift}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existingShift?.shiftName ?? '');

    TimeOfDay startTime = existingShift != null
        ? _parseTimeOfDay(existingShift.startTime)
        : const TimeOfDay(hour: 9, minute: 0);

    TimeOfDay endTime = existingShift != null
        ? _parseTimeOfDay(existingShift.endTime)
        : const TimeOfDay(hour: 18, minute: 0);

    TimeOfDay deadlineTime = existingShift != null
        ? _parseTimeOfDay(existingShift.maxCheckInTime)
        : const TimeOfDay(hour: 9, minute: 15);

    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.alarm_add_rounded, color: AppColors.kesariSaffron),
                  const SizedBox(width: 10),
                  Text(
                    existingShift != null ? 'Edit Shift Settings' : 'Create Custom Shift',
                    style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Shift Name',
                          hintText: 'e.g. General Shift, Morning Shift A',
                          labelStyle: const TextStyle(color: AppColors.textMuted),
                          filled: true,
                          fillColor: AppColors.inputBgDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Shift name is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Start Time Picker Tile
                      _buildTimePickerTile(
                        context: context,
                        label: 'Shift Start Time',
                        time: startTime,
                        icon: Icons.access_time_filled_rounded,
                        onTimePicked: (picked) => setDialogState(() => startTime = picked),
                      ),
                      const SizedBox(height: 10),

                      // End Time Picker Tile
                      _buildTimePickerTile(
                        context: context,
                        label: 'Shift End Time',
                        time: endTime,
                        icon: Icons.history_toggle_off_rounded,
                        onTimePicked: (picked) => setDialogState(() => endTime = picked),
                      ),
                      const SizedBox(height: 10),

                      // Check-in Deadline Picker Tile
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.kesariSaffron.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.kesariSaffron.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.timer_off_rounded, color: AppColors.kesariSaffron, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  'Max Allowed Check-In Time',
                                  style: GoogleFonts.inter(color: AppColors.kesariSaffron, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Attendance past this time requires Admin Approval & Late Reason',
                              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
                            ),
                            const SizedBox(height: 8),
                            _buildTimePickerTile(
                              context: context,
                              label: 'Last Check-In Cutoff',
                              time: deadlineTime,
                              icon: Icons.lock_clock_rounded,
                              onTimePicked: (picked) => setDialogState(() => deadlineTime = picked),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.kesariSaffron,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);

                          try {
                            final String shiftId = existingShift?.shiftId ?? const Uuid().v4();
                            final shift = ShiftModel(
                              shiftId: shiftId,
                              businessId: widget.businessId,
                              shopId: widget.shopId,
                              shiftName: nameCtrl.text.trim(),
                              startTime: _formatTimeOfDay(startTime),
                              endTime: _formatTimeOfDay(endTime),
                              maxCheckInTime: _formatTimeOfDay(deadlineTime),
                              createdAt: existingShift?.createdAt ?? DateTime.now(),
                            );

                            // Save to Cloud Firestore
                            await FirebaseFirestore.instance
                                .collection(AppConstants.colBusinesses)
                                .doc(widget.businessId)
                                .collection('shifts')
                                .doc(shiftId)
                                .set(shift.toMap());

                            // Cache to Local SQLite DB
                            await _offlineDb.saveLocalShifts([shift.toMap()]);

                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Error saving shift: $e'), backgroundColor: AppColors.sindoorRed),
                              );
                            }
                          } finally {
                            setDialogState(() => isSaving = false);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('SAVE SHIFT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteShift(String shiftId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Delete Shift', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Are you sure you want to delete this shift?', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.sindoorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection(AppConstants.colBusinesses)
            .doc(widget.businessId)
            .collection('shifts')
            .doc(shiftId)
            .delete();
      } catch (e) {
        debugPrint('Error deleting shift: $e');
      }
    }
  }

  TimeOfDay _parseTimeOfDay(String str) {
    try {
      final clean = str.trim().toUpperCase();
      bool isPm = clean.contains('PM');
      bool isAm = clean.contains('AM');
      String text = clean.replaceAll('AM', '').replaceAll('PM', '').trim();
      final parts = text.split(':');
      int h = int.parse(parts[0]);
      int m = parts.length > 1 ? int.parse(parts[1]) : 0;
      if (isPm && h < 12) h += 12;
      if (isAm && h == 12) h = 0;
      return TimeOfDay(hour: h, minute: m);
    } catch (_) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  Widget _buildTimePickerTile({
    required BuildContext context,
    required String label,
    required TimeOfDay time,
    required IconData icon,
    required Function(TimeOfDay) onTimePicked,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: time);
        if (picked != null) onTimePicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.inputBgDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorderDark),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.haldiGold, size: 20),
                const SizedBox(width: 10),
                Text(label, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
            Text(
              _formatTimeOfDay(time),
              style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
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
        title: Text('Shift Settings & Rules', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(AppConstants.colBusinesses)
            .doc(widget.businessId)
            .collection('shifts')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.kesariSaffron));
          }

          final docs = snapshot.data?.docs ?? [];
          final shifts = docs.map((doc) => ShiftModel.fromMap(doc.data() as Map<String, dynamic>)).toList();

          // Sync shifts to local SQLite DB
          if (shifts.isNotEmpty) {
            _offlineDb.saveLocalShifts(shifts.map((s) => s.toMap()).toList());
          }

          if (shifts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.alarm_off_rounded, color: AppColors.textMuted, size: 60),
                  const SizedBox(height: 12),
                  Text('No Custom Shifts Configured', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Tap + Add Shift to define work timing & check-in deadline.', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.kesariSaffron),
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: const Text('ADD SHIFT NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => _showAddEditShiftDialog(),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: shifts.length,
            itemBuilder: (context, index) {
              final shift = shifts[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
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
                            const Icon(Icons.schedule_rounded, color: AppColors.kesariSaffron, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              shift.shiftName,
                              style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.haldiGold, size: 20),
                              onPressed: () => _showAddEditShiftDialog(existingShift: shift),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.sindoorRed, size: 20),
                              onPressed: () => _deleteShift(shift.shiftId),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.inputBgDark,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Timing', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text('${shift.startTime} - ${shift.endTime}', style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.kesariSaffron.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.kesariSaffron.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Last Check-In Cutoff', style: GoogleFonts.inter(color: AppColors.kesariSaffron, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text('Till ${shift.maxCheckInTime}', style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.kesariSaffron,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('ADD SHIFT', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
        onPressed: () => _showAddEditShiftDialog(),
      ),
    );
  }
}
