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

  // Catch all unhandled Flutter framework errors safely
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('⚠️ Flutter Framework Exception caught: ${details.exception}');
  };

  // Custom global error widget fallback to prevent app crash screens
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: AppColors.bgDark,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.kesariSaffron, size: 56),
              const SizedBox(height: 16),
              Text(
                'Smart Attendance Ecosystem',
                style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Application protected from unexpected rendering error.',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.kesariSaffron),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text('RELOAD APP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  runApp(const AttendanceApp(savedSession: null));
                },
              ),
            ],
          ),
        ),
      ),
    );
  };

  Map<String, dynamic>? savedSession;

  try {
    // Initialize Firebase with generated options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Start background auto sync engine for offline attendance
    try {
      SyncEngine().startAutoSync();
    } catch (e) {
      debugPrint('SyncEngine startAutoSync notice: $e');
    }

    // Check saved persistent user session
    try {
      final authService = AuthRoutingService();
      savedSession = await authService.getSavedSession();
    } catch (e) {
      debugPrint('getSavedSession notice: $e');
    }
  } catch (e) {
    debugPrint('Firebase.initializeApp notice: $e');
  }

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
