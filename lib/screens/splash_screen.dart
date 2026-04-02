import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/preferences_service.dart';
import 'language_picker_screen.dart';
import 'onboarding_screen.dart';
import 'auth_gateway.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    
    _controller.forward();
    _routeUser();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _routeUser() async {
    // Retrasar para disfrutar el logo Fade-in (VisionOS Splash)
    await Future.delayed(const Duration(milliseconds: 2000));

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

    // Ya vio onboarding y tiene idioma, delegamos la sesión a Firebase a través del AuthGateway
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthGateway()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_volleyball, size: 120, color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'OMNISPORT-AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
