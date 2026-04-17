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
      body: Center(
        child: Image.asset(
          'assets/images/app_logo_shield.png',
          width: 150, // Tamaño similar al native splash
        ),
      ),
    );
  }
}
