import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/preferences_service.dart';
import '../l10n/app_localizations.dart';
import 'auth_gateway.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  Future<void> _completeOnboarding() async {
    await PreferencesService().setHasSeenOnboarding(true);
    
    if (!mounted) return;
    
    // Al completar, delegar a AuthGateway para manejar la sesión final
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthGateway()),
    );
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _completeOnboarding,
            child: Text(loc.skip, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  children: [
                    // Slide 1
                    _buildSlide(
                      icon: CupertinoIcons.person,
                      title: loc.onboardingSlide1Title,
                      description: loc.onboardingSlide1Desc,
                    ),
                    // Slide 2
                    _buildSlide(
                      icon: CupertinoIcons.sparkles, // Representa IA
                      title: loc.onboardingSlide2Title,
                      description: loc.onboardingSlide2Desc,
                    ),
                    // Slide 3
                    _buildSlide(
                      icon: CupertinoIcons.lock_shield, // Representa Legal / Seguridad
                      title: loc.onboardingSlide3Title,
                      description: loc.onboardingSlide3Desc,
                    ),
                  ],
                ),
              ),
              
              // Paginador
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) => _buildDot(index: index)),
              ),
              
              const SizedBox(height: 32),
              
              // Botón Inferior
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF003F87),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 5,
                      shadowColor: Colors.black45,
                    ),
                    child: Text(
                      _currentPage == 2 ? loc.start : loc.next,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlide({required IconData icon, required String title, required String description}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32), // Geometría Squircle / Suave
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
            child: Container(
              padding: const EdgeInsets.all(40.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2), // Borde reflectivo 20%
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 80, color: Colors.white),
                  const SizedBox(height: 32),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15, 
                      color: Colors.white70, 
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDot({required int index}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 5),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index ? Colors.white : Colors.white.withOpacity(0.4),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
