import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart'; // import appLocaleNotifier
import 'onboarding_screen.dart';

class LanguagePickerScreen extends StatelessWidget {
  const LanguagePickerScreen({super.key});

  Future<void> _selectLanguage(BuildContext context, String code) async {
    // Guardar preferencia
    await PreferencesService().setPreferredLanguage(code);
    
    // Actualizar State Global Notifier para que AppLocalizations mute al instante
    appLocaleNotifier.value = Locale(code);

    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.language, size: 80, color: Color(0xFF003F87)),
              const SizedBox(height: 32),
              Text(
                loc.languagePickerTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
              ),
              const SizedBox(height: 48),
              
              // Botón Español
              ElevatedButton(
                onPressed: () => _selectLanguage(context, 'es'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003F87),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(loc.languagePickerEs, style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
              
              const SizedBox(height: 20),
              
              // Botón Inglés
              OutlinedButton(
                onPressed: () => _selectLanguage(context, 'en'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF003F87), width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(loc.languagePickerEn, style: const TextStyle(color: Color(0xFF003F87), fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
