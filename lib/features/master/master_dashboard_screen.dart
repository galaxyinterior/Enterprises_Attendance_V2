import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/shop_provisioning_service.dart';
import '../../models/registration_request_model.dart';
import '../../models/business_model.dart';
import '../auth/login_screen.dart';

class MasterDashboardScreen extends StatefulWidget {
  const MasterDashboardScreen({super.key});

  @override
  State<MasterDashboardScreen> createState() => _MasterDashboardScreenState();
}

class _MasterDashboardScreenState extends State<MasterDashboardScreen> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF6366F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Text('MASTER CONTROL PANEL', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Sign Out',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Metrics Bar
          _buildMetricsBar(),
          
          // Navigation Tabs
          Container(
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                _buildTabButton('Pending Requests', 0, Icons.assignment_outlined),
                _buildTabButton('Registered Shops', 1, Icons.store_rounded),
                _buildTabButton('System Health & Audit Logs', 2, Icons.health_and_safety_outlined),
              ],
            ),
          ),

          // Tab Body
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildPendingRequestsTab(),
                _buildShopsDirectoryTab(),
                _buildAuditLogsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsBar() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(AppConstants.colBusinesses).snapshots(),
      builder: (context, snapshot) {
        int totalShops = 0;
        int activeShops = 0;
        int pausedShops = 0;

        if (snapshot.hasData) {
          totalShops = snapshot.data!.docs.length;
          for (var doc in snapshot.data!.docs) {
            final status = doc.get('status') ?? '';
            if (status == AppConstants.statusActive) activeShops++;
            if (status == AppConstants.statusPaused) pausedShops++;
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          color: const Color(0xFF0F172A),
          child: Row(
            children: [
              Expanded(child: _buildMetricCard('Total Shops', '$totalShops', Colors.indigoAccent, Icons.storefront_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildMetricCard('Active Shops', '$activeShops', Colors.greenAccent, Icons.check_circle_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildMetricCard('Paused Shops', '$pausedShops', Colors.amberAccent, Icons.pause_circle_rounded)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(count, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(title, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index, IconData icon) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF94A3B8), size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.colRegistrationRequests)
          .where('status', isEqualTo: AppConstants.statusPending)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.task_alt_rounded, size: 56, color: Colors.greenAccent),
                const SizedBox(height: 12),
                Text('No Pending Applications', style: GoogleFonts.outfit(fontSize: 18, color: Colors.white)),
                Text('All new shop registrations have been processed.', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final request = RegistrationRequestModel.fromMap(data);

            return Card(
              color: const Color(0xFF1E293B),
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(request.shopName, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        Chip(
                          label: Text(request.applicationId, style: const TextStyle(color: Colors.white, fontSize: 11)),
                          backgroundColor: const Color(0xFF6366F1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Owner: ${request.ownerName} | Phone: ${request.phone} | Email: ${request.email}', style: GoogleFonts.inter(color: const Color(0xFFCBD5E1))),
                    Text('Location: ${request.city}, ${request.state} | Staff: ${request.employeeCount}', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: const Text('APPROVE & PROVISION SHOP', style: TextStyle(color: Colors.white)),
                          onPressed: () => _approveRequest(request),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                          icon: const Icon(Icons.close),
                          label: const Text('REJECT'),
                          onPressed: () => _rejectRequest(request),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _generateAutoPassword(String rolePrefix) {
    final randomNum = 1000 + Random().nextInt(9000);
    return '$rolePrefix@$randomNum';
  }

  void _approveRequest(RegistrationRequestModel request) async {
    final defaultShopId = 'SHOP${const Uuid().v4().substring(0, 4).toUpperCase()}';
    final shopIdController = TextEditingController(text: defaultShopId);
    final adminPasswordController = TextEditingController(text: _generateAutoPassword('Admin'));
    final kioskPasswordController = TextEditingController(text: _generateAutoPassword('Kiosk'));
    final emailController = TextEditingController(text: request.email);

    final formKey = GlobalKey<FormState>();
    bool isProcessing = false;
    bool obscureAdminPass = true;
    bool obscureKioskPass = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentShopId = shopIdController.text.trim().toUpperCase();
            final adminEmailPreview = currentShopId.isNotEmpty ? '$currentShopId@admin.in' : '-';
            final kioskEmailPreview = currentShopId.isNotEmpty ? '$currentShopId@kiosk.in' : '-';

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Colors.greenAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Approve & Provision Shop', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(request.shopName, style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 480,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Shop ID & Passwords are auto-generated. You can customize them or click 🔄 to re-generate.',
                          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                        ),
                        const SizedBox(height: 16),

                        // Manual Shop ID Field
                        TextFormField(
                          controller: shopIdController,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
                          decoration: InputDecoration(
                            labelText: 'Shop ID (Editable)',
                            labelStyle: const TextStyle(color: Color(0xFF818CF8)),
                            hintText: 'e.g. SHOP001',
                            prefixIcon: const Icon(Icons.fingerprint, color: Color(0xFF818CF8)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.white70),
                              tooltip: 'Auto-generate new Shop ID',
                              onPressed: () {
                                setDialogState(() {
                                  shopIdController.text = 'SHOP${const Uuid().v4().substring(0, 4).toUpperCase()}';
                                });
                              },
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Shop ID cannot be empty';
                            if (val.trim().length < 3) return 'Shop ID must be at least 3 chars';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // User Email Address Field
                        TextFormField(
                          controller: emailController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Recipient Email Address',
                            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF818CF8)),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty || !val.contains('@')) return 'Enter a valid email address';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Admin Password Field
                        TextFormField(
                          controller: adminPasswordController,
                          obscureText: obscureAdminPass,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Shop Admin Password (Auto-generated)',
                            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF818CF8)),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded, color: Colors.amberAccent),
                                  tooltip: 'Re-generate Auto Password',
                                  onPressed: () {
                                    setDialogState(() {
                                      adminPasswordController.text = _generateAutoPassword('Admin');
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: Icon(obscureAdminPass ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
                                  onPressed: () => setDialogState(() => obscureAdminPass = !obscureAdminPass),
                                ),
                              ],
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) => (val == null || val.trim().length < 6) ? 'Password must be at least 6 characters' : null,
                        ),
                        const SizedBox(height: 14),

                        // Kiosk Password Field
                        TextFormField(
                          controller: kioskPasswordController,
                          obscureText: obscureKioskPass,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Kiosk App Password (Auto-generated)',
                            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.desktop_windows_outlined, color: Color(0xFF38BDF8)),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded, color: Colors.cyanAccent),
                                  tooltip: 'Re-generate Auto Password',
                                  onPressed: () {
                                    setDialogState(() {
                                      kioskPasswordController.text = _generateAutoPassword('Kiosk');
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: Icon(obscureKioskPass ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
                                  onPressed: () => setDialogState(() => obscureKioskPass = !obscureKioskPass),
                                ),
                              ],
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) => (val == null || val.trim().length < 6) ? 'Password must be at least 6 characters' : null,
                        ),
                        const SizedBox(height: 16),

                        // Live Credentials Preview Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('GENERATED LOGIN CREDENTIALS:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.admin_panel_settings, color: Color(0xFF818CF8), size: 16),
                                  const SizedBox(width: 6),
                                  Text('Admin ID: ', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                                  Text(adminEmailPreview, style: GoogleFonts.inter(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.computer, color: Color(0xFF38BDF8), size: 16),
                                  const SizedBox(width: 6),
                                  Text('Kiosk ID: ', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                                  Text(kioskEmailPreview, style: GoogleFonts.inter(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: isProcessing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  label: Text(
                    isProcessing ? 'PROVISIONING...' : 'PROVISION & SEND MAIL',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isProcessing = true);

                          final result = await ShopProvisioningService().provisionShop(
                            request: request,
                            customShopId: shopIdController.text,
                            adminPassword: adminPasswordController.text,
                            kioskPassword: kioskPasswordController.text,
                            userEmail: emailController.text,
                          );

                          if (!dialogCtx.mounted) return;
                          Navigator.pop(dialogCtx);

                          if (!mounted) return;

                          if (result.success) {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: const Color(0xFF1E293B),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
                                    const SizedBox(width: 10),
                                    Text('Shop Provisioned!', style: GoogleFonts.outfit(color: Colors.white)),
                                  ],
                                ),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Assigned Shop ID: ${result.shopId}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 12),
                                    Text('Firebase Auth Admin: ${result.adminEmail}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    Text('Firebase Auth Kiosk: ${result.kioskEmail}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: result.emailSent ? Colors.green.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: result.emailSent ? Colors.greenAccent : Colors.amberAccent),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(result.emailSent ? Icons.mark_email_read : Icons.warning_amber_rounded,
                                              color: result.emailSent ? Colors.greenAccent : Colors.amberAccent, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              result.emailSent
                                                  ? 'Credentials Email successfully sent to ${emailController.text}!'
                                                  : 'Shop provisioned but credentials email could not be sent. Check SMTP credentials.',
                                              style: TextStyle(color: result.emailSent ? Colors.greenAccent : Colors.amberAccent, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Provisioning Failed: ${result.errorMessage}'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
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

  void _rejectRequest(RegistrationRequestModel request) async {
    await FirebaseFirestore.instance
        .collection(AppConstants.colRegistrationRequests)
        .doc(request.applicationId)
        .update({'status': AppConstants.statusRejected});
  }

  Widget _buildShopsDirectoryTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(AppConstants.colBusinesses).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final biz = BusinessModel.fromMap(data);
            final isPaused = biz.status == AppConstants.statusPaused;

            return Card(
              color: const Color(0xFF1E293B),
              margin: const EdgeInsets.only(bottom: 14),
              child: ListTile(
                title: Text(biz.shopName, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('ID: ${biz.shopId} | Owner: ${biz.ownerName} | City: ${biz.city}', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(biz.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: isPaused ? Colors.amber : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPaused ? Colors.green : Colors.amber.shade800,
                      ),
                      onPressed: () => _toggleShopStatus(biz),
                      child: Text(isPaused ? 'RESUME SHOP' : 'PAUSE SHOP', style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toggleShopStatus(BusinessModel biz) async {
    final newStatus = biz.status == AppConstants.statusActive
        ? AppConstants.statusPaused
        : AppConstants.statusActive;

    await FirebaseFirestore.instance
        .collection(AppConstants.colBusinesses)
        .doc(biz.businessId)
        .update({
      'status': newStatus,
      'pausedAt': newStatus == AppConstants.statusPaused ? DateTime.now().toIso8601String() : null,
      'pauseReason': newStatus == AppConstants.statusPaused ? 'Paused by Master Admin' : null,
    });
  }

  Widget _buildAuditLogsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_outlined, color: Colors.indigoAccent, size: 64),
          const SizedBox(height: 16),
          Text('Master Audit Trail Active', style: GoogleFonts.outfit(fontSize: 18, color: Colors.white)),
          Text('All administrative actions and security operations are logged to Firestore.', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}
