import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/preferences_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart'; // import appLocaleNotifier
import 'onboarding_screen.dart';

class LanguagePickerScreen extends StatelessWidget {
  final bool fromLogin;
  
  const LanguagePickerScreen({super.key, this.fromLogin = false});

  Future<void> _selectLanguage(BuildContext context, String code) async {
    // Guardar preferencia
    await PreferencesService().setPreferredLanguage(code);
    
    // Actualizar State Global Notifier para que la app se traduzca al instante
    appLocaleNotifier.value = Locale(code);

    if (context.mounted) {
      if (fromLogin) {
        // Retorna al login sin generar nueva pantalla en pila
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Para ver los textos iniciales antes de setear un Locale, podemos apoyarnos en la traducción actual.
    final loc = AppLocalizations.of(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: fromLogin ? AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.clear, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ) : null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                  child: Container(
                    padding: const EdgeInsets.all(40.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2), 
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(CupertinoIcons.globe, size: 80, color: Colors.white),
                        const SizedBox(height: 32),
                        Text(
                          loc.languagePickerTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 48),
                        
                        // Botón Español
                        ElevatedButton(
                          onPressed: () => _selectLanguage(context, 'es'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 5,
                            shadowColor: Colors.black45,
                          ),
                          child: Text(loc.languagePickerEs, style: const TextStyle(color: Color(0xFF003F87), fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Botón Inglés
                        OutlinedButton(
                          onPressed: () => _selectLanguage(context, 'en'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white, width: 2),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(loc.languagePickerEn, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
