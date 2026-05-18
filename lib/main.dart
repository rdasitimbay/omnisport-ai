import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/splash_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/auth_gateway.dart';
import 'screens/login_screen.dart';
import 'firebase_options.dart';
import 'services/preferences_service.dart';
import 'services/secure_hive_service.dart';
import 'widgets/debug_sync_overlay.dart';
import 'services/offline_sync_service.dart';
import 'l10n/app_localizations.dart';

// Gestor de estado global y ultraligero para el idioma de la app
final ValueNotifier<Locale> appLocaleNotifier = ValueNotifier(
  const Locale('es'),
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('Notificación en background/terminada: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    const useEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: false);
    if (kDebugMode && useEmulator) {
      try {
        final host = !kIsWeb && Platform.isAndroid ? '10.0.2.2' : 'localhost';
        FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
        await FirebaseAuth.instance.useAuthEmulator(host, 9099);
        FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
        FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(host, 5001);
        debugPrint('Firebase Emulators connected (Firestore on 8080, Auth on 9099, Functions on 5001)');
      } catch (e) {
        debugPrint('Error connecting to emulators: $e');
      }
    }

    // Habilitar persistencia offline para Firestore (Modo Torneo sin red/Cache local)
    // Se debe configurar *después* de llamar a useFirestoreEmulator
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Iniciar el Singleton de Preferencias
    await PreferencesService().init();

    // Iniciar el servicio offline seguro de Hive (TKT-004)
    await SecureHiveService.init();
    await OfflineSyncService.init();
    OfflineSyncService.syncLogs(); // Intentar sincronizar pendientes en background
    // Configurar idioma guardado
    final lang = PreferencesService().preferredLanguage;
    if (lang != null) {
      appLocaleNotifier.value = Locale(lang);
    }

    // Configurar persistencia local para mantener la sesión abierta
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);

    if (kIsWeb) {
      final redirectResult = await FirebaseAuth.instance.getRedirectResult();
      if (redirectResult != null && redirectResult.user != null) {
        debugPrint(
          "Redirect detectado con éxito: ${redirectResult.user?.email}",
        );
        final user = redirectResult.user!;
        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final docSnap = await docRef.get();
        if (!docSnap.exists) {
          // Assign admin role if it's the owner's email, otherwise user
          final role = (user.email == 'asitimbay.rommel@gmail.com' || user.email == 'admin@omnisport.ai') ? 'admin' : 'user';
          await docRef.set({
            'email': user.email ?? 'Sin correo',
            'role': role,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    try {
      final token = await messaging.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (token != null && user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'fcmLastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error obteniendo FCM token: $e");
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
        "Notificación recibida en primer plano: ${message.notification?.title}",
      );
      // Sync Sentinel Feedback en vivo
      OfflineSyncService.syncLogs();
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
          supportedLocales: const [Locale('es', ''), Locale('en', '')],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF003F87),
            ),
            useMaterial3: true,
            fontFamily: 'Inter',
            canvasColor:
                Colors.transparent, // Permite que el fondo de cristal brille
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
          builder: (context, child) {
            return Stack(
              children: [
                if (child != null) child,
                if (kDebugMode) const DebugSyncOverlay(),
              ],
            );
          },
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Scaffold(
                  backgroundColor: const Color(0xFF001F3F),
                  body: Center(
                    child: Text(
                      "Auth Error: ${snapshot.error}",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SplashScreen();
              }
              final user = snapshot.data;
              if (user != null) {
                debugPrint("--- USUARIO AUTENTICADO: ${user.uid} ---");
                return const AuthGateway();
              }
              return const LoginScreen();
            },
          ),
        );
      },
    );
  }
}
