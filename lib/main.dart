import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/dashboard_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase initialization failed. Error: $e");
  }

  runApp(const OmniSportApp());
}

class OmniSportApp extends StatelessWidget {
  const OmniSportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniSport-AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF003F87)),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const DashboardScreen(
        // Este es un ID de prueba (mock) para leer de Firestore
        currentAthleteId: 'athlete_demo_123',
      ),
    );
  }
}
