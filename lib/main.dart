import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/splash_screen.dart';
import 'firebase_options.dart';
import 'services/preferences_service.dart';
import 'l10n/app_localizations.dart';

// Gestor de estado global y ultraligero para el idioma de la app
final ValueNotifier<Locale> appLocaleNotifier = ValueNotifier(const Locale('es'));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Iniciar el Singleton de Preferencias
    await PreferencesService().init();
    
    // Configurar idioma guardado
    final lang = PreferencesService().preferredLanguage;
    if (lang != null) {
      appLocaleNotifier.value = Locale(lang);
    }
    
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      final redirectResult = await FirebaseAuth.instance.getRedirectResult();
      if (redirectResult.user != null) {
        debugPrint("Redirect detectado con éxito: ${redirectResult.user?.email}");
      }
    }
    
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Notificación recibida en primer plano: ${message.notification?.title}");
    });

  } catch (e) {
    debugPrint("App init error: $e");
  }

  runApp(const OmniSportApp());
}

class OmniSportApp extends StatelessWidget {
  const OmniSportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, child) {
        return MaterialApp(
          title: 'OmniSport-AI',
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('es', ''),
            Locale('en', ''),
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF003F87)),
            useMaterial3: true,
            fontFamily: 'Inter',
            canvasColor: Colors.transparent, // Permite que el fondo de cristal brille
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
