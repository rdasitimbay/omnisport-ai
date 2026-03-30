import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // 1. Configurar Persistencia Inmediata
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      
      // 2. Capturar resultado de redirección ANTES de arrancar la App
      // Esto evita que authStateChanges emita null erróneamente durante la carga
      final redirectResult = await FirebaseAuth.instance.getRedirectResult();
      if (redirectResult.user != null) {
        debugPrint("Redirect detectado con éxito: ${redirectResult.user?.email}");
      }
    }
    
    // 3. Configuración básica de Notificaciones Push
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
    debugPrint("Firebase init error: $e");
  }

  runApp(const OmniSportApp());
}

class OmniSportApp extends StatelessWidget {
  const OmniSportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniSport-AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF003F87)),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return DashboardScreen(
              currentAthleteId: snapshot.data!.uid, 
            );
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
