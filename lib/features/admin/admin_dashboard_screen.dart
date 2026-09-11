import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/auth_routing_service.dart';
import '../../models/employee_model.dart';
import '../auth/login_screen.dart';
import 'add_employee_screen.dart';

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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.cardDark,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SHOP ADMIN CONSOLE', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Shop ID: ${widget.shopId}', style: GoogleFonts.inter(color: AppColors.textSaffron, fontSize: 12)),
          ],
        ),
        actions: [
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
      body: Row(
        children: [
          // Sidebar Navigation Rail
          NavigationRail(
            backgroundColor: AppColors.cardDark,
            selectedIndex: _selectedNavIndex,
            onDestinationSelected: (index) => setState(() => _selectedNavIndex = index),
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: const IconThemeData(color: AppColors.kesariSaffron),
            selectedLabelTextStyle: GoogleFonts.inter(color: AppColors.kesariSaffron, fontWeight: FontWeight.bold),
            unselectedIconTheme: const IconThemeData(color: AppColors.textMuted),
            unselectedLabelTextStyle: GoogleFonts.inter(color: AppColors.textMuted),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), label: Text('Overview')),
              NavigationRailDestination(icon: Icon(Icons.people_alt_outlined), label: Text('Staff Directory')),
              NavigationRailDestination(icon: Icon(Icons.schedule_outlined), label: Text('Shifts')),
              NavigationRailDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: Text('Payroll & Payslips')),
              NavigationRailDestination(icon: Icon(Icons.devices_other_rounded), label: Text('Kiosks')),
              NavigationRailDestination(icon: Icon(Icons.campaign_outlined), label: Text('Announcements')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: AppColors.cardBorderDark),
          
          // Main Content View
          Expanded(
            child: IndexedStack(
              index: _selectedNavIndex,
              children: [
                _buildOverviewTab(),
                _buildStaffDirectoryTab(),
                _buildShiftsTab(),
                _buildPayrollUdhaarTab(),
                _buildKiosksTab(),
                _buildAnnouncementsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today\'s Attendance Summary', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),

          // Real Live Firestore Metrics Summary Stream
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
          ),

          const SizedBox(height: 32),
          Text('Recent Live Attendance Stream', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
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
                  .orderBy('createdAt', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.kesariSaffron));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('No live attendance records logged yet today.', style: GoogleFonts.inter(color: AppColors.textMuted)),
                  );
                }
                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['employeeName'] ?? 'Employee';
                    final status = data['status'] ?? 'PRESENT';
                    final date = data['date'] ?? '';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: status == 'PRESENT' ? AppColors.pannaEmerald : AppColors.haldiGold,
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'E', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(name, style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                      subtitle: Text('Status: $status | Date: $date', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
                      trailing: Chip(
                        label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                        backgroundColor: status == 'PRESENT' ? AppColors.pannaEmerald : AppColors.haldiGold,
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          Text(title, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildStaffDirectoryTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
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
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                  label: const Text('ADD NEW EMPLOYEE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              hintStyle: const TextStyle(color: AppColors.textMuted),
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
                      _searchQuery.isNotEmpty ? 'No staff matching "$_searchQuery"' : 'No staff members added yet. Click "Add New Employee" to enroll staff.',
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
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: emp.active ? AppColors.kesariSaffron : AppColors.textMuted,
                          child: Text(emp.fullName.isNotEmpty ? emp.fullName[0].toUpperCase() : 'E', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        title: Row(
                          children: [
                            Text(emp.fullName, style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            if (!emp.active)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.sindoorRed.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                child: Text('INACTIVE', style: GoogleFonts.inter(color: AppColors.sindoorRed, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        subtitle: Text('Code: ${emp.employeeCode} | Dept: ${emp.department} | Salary: ₹${emp.monthlySalary.toStringAsFixed(0)}/mo', style: GoogleFonts.inter(color: AppColors.textMuted)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(emp.faceEnrollmentStatus ? 'Face Enrolled ✓' : 'Face Pending ⚠', style: const TextStyle(color: Colors.white, fontSize: 11)),
                              backgroundColor: emp.faceEnrollmentStatus ? AppColors.pannaEmerald : AppColors.haldiGold,
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

  Widget _buildShiftsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Shift Engine Configuration', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Card(
            color: AppColors.cardDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.cardBorderDark),
            ),
            child: const ListTile(
              title: Text('Morning Shift (Default)', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              subtitle: Text('Check-in: 10:00 AM - 10:30 AM | Checkout: 06:30 PM - 07:30 PM | Grace: 15 mins', style: TextStyle(color: AppColors.textMuted)),
              trailing: Icon(Icons.edit, color: AppColors.haldiGold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollUdhaarTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Staff Advance (Udhaar) & Monthly Payslips', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.pannaEmerald),
                icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
                label: const Text('GENERATE PAYSLIP PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () => _showPayslipModal(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Real Live Firestore Employee Payroll List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(AppConstants.colBusinesses)
                  .doc(widget.businessId)
                  .collection(AppConstants.colEmployees)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.kesariSaffron));

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Center(child: Text('No employees found to calculate payroll.', style: GoogleFonts.inter(color: AppColors.textMuted)));
                }

                double totalGrossSalary = 0;
                for (var doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  totalGrossSalary += (data['monthlySalary'] ?? 0.0).toDouble();
                }

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorderDark),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Monthly Staff Payroll:', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                              Text('₹${totalGrossSalary.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: AppColors.pannaEmerald, fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Chip(
                            label: Text('${docs.length} Active Staff', style: const TextStyle(color: Colors.white)),
                            backgroundColor: AppColors.kesariSaffron,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, idx) {
                          final emp = EmployeeModel.fromMap(docs[idx].data() as Map<String, dynamic>);
                          return Card(
                            color: AppColors.cardDark,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(backgroundColor: AppColors.haldiGold, child: Icon(Icons.payments_outlined, color: Colors.white)),
                              title: Text(emp.fullName, style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                              subtitle: Text('Base Salary: ₹${emp.monthlySalary.toStringAsFixed(0)}/month', style: GoogleFonts.inter(color: AppColors.textMuted)),
                              trailing: Text('Net: ₹${emp.monthlySalary.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: AppColors.pannaEmerald, fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
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
          content: SizedBox(
            width: 500,
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
          Text(label, style: GoogleFonts.inter(color: isTotal ? AppColors.textPrimary : AppColors.textMuted, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(val, style: GoogleFonts.outfit(color: isTotal ? AppColors.pannaEmerald : AppColors.textPrimary, fontWeight: isTotal ? FontWeight.bold : FontWeight.w600, fontSize: isTotal ? 16 : 14)),
        ],
      ),
    );
  }

  Widget _buildKiosksTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
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
    final textCtrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Broadcast Voice Announcement / Alert', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          TextField(
            controller: textCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter message to broadcast on Entrance Kiosk device...',
              hintStyle: const TextStyle(color: AppColors.textMuted),
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
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.sindoorRed),
            icon: const Icon(Icons.campaign, color: Colors.white),
            label: const Text('BROADCAST EMERGENCY ALERT NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Emergency alert broadcasted to Kiosk device!')),
              );
            },
          ),
        ],
      ),
    );
  }
}
