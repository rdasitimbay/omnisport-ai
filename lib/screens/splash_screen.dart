import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/preferences_service.dart';
import 'language_picker_screen.dart';
import 'onboarding_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  
  @override
  void initState() {
    super.initState();
    _routeUser();
  }

  Future<void> _routeUser() async {
    // Simulamos un pequeño delay para que se vea el Splash
    await Future.delayed(const Duration(milliseconds: 800));

    final prefs = PreferencesService();

    if (!mounted) return;

    if (prefs.preferredLanguage == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LanguagePickerScreen()));
      return;
    }

    if (!prefs.hasSeenOnboarding) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      return;
    }

    // Ya vio onboarding y tiene idioma, verificamos Firebase Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(currentAthleteId: user.uid)));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF003F87),
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
