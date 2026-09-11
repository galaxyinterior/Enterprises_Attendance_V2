import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'core/services/sync_engine.dart';
import 'core/services/auth_routing_service.dart';
import 'core/constants/app_constants.dart';
import 'core/constants/app_colors.dart';
import 'features/auth/login_screen.dart';
import 'features/master/master_dashboard_screen.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/kiosk/kiosk_attendance_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with generated options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Start background auto sync engine for offline attendance
  SyncEngine().startAutoSync();

  // Check saved persistent user session
  final authService = AuthRoutingService();
  final savedSession = await authService.getSavedSession();

  runApp(AttendanceApp(savedSession: savedSession));
}

class AttendanceApp extends StatelessWidget {
  final Map<String, dynamic>? savedSession;

  const AttendanceApp({super.key, this.savedSession});

  @override
  Widget build(BuildContext context) {
    Widget initialScreen = const LoginScreen();

    if (savedSession != null) {
      final role = savedSession!['role'] ?? '';
      final shopId = savedSession!['shopId'] ?? 'SHOP001';
      final businessId = savedSession!['businessId'] ?? shopId;

      if (role == AppConstants.roleMaster) {
        initialScreen = const MasterDashboardScreen();
      } else if (role == AppConstants.roleKiosk) {
        initialScreen = KioskAttendanceScreen(shopId: shopId, businessId: businessId);
      } else if (role == AppConstants.roleShopAdmin) {
        initialScreen = AdminDashboardScreen(shopId: shopId, businessId: businessId);
      }
    }

    return MaterialApp(
      title: 'Smart Attendance Ecosystem',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bgDark,
        cardColor: AppColors.cardDark,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.kesariSaffron,
          secondary: AppColors.haldiGold,
          surface: AppColors.cardDark,
        ),
      ),
      home: initialScreen,
    );
  }
}
