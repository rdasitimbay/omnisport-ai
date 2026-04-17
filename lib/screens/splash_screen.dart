import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
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

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _routeUser();
  }

  Future<void> _routeUser() async {
    // Delay de 1.5s para disfrutar el branding antes de rutear
    await Future.delayed(const Duration(milliseconds: 1500));

    final prefs = PreferencesService();
    if (!mounted) return;

    Widget targetScreen;
    if (prefs.preferredLanguage == null) {
      targetScreen = const LanguagePickerScreen();
    } else if (!prefs.hasSeenOnboarding) {
      targetScreen = const OnboardingScreen();
    } else {
      // Ya vio onboarding y tiene idioma, delegamos la sesión a Firebase a través del AuthGateway
      targetScreen = const AuthGateway();
    }

    // Transición FadeIn suave hacia la siguiente pantalla
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      body: Shimmer.fromColors(
        baseColor: Colors.white,
        highlightColor: Colors.grey.shade400,
        period: const Duration(milliseconds: 2000),
        child: Stack(
          children: [
            Center(
              child: Image.asset(
                'assets/images/app_logo_shield_premium_fin.png',
                width: 127, // 15% de reduccion de 150
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Text(
                'POWERED BY ROMMEL ASITIMBAY MORALES',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 10,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w300,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
