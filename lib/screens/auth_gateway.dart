import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

class AuthGateway extends StatelessWidget {
  const AuthGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Mientras Firebase evalúa la sesión, mostramos el cargador espacial
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              ),
            ),
          );
        }

        // Si Firebase reporta credenciales activas, monta Dashboard,
        // destruyendo permanentemente LoginScreen del árbol de la app.
        if (snapshot.hasData && snapshot.data != null) {
          return DashboardScreen(currentAthleteId: snapshot.data!.uid);
        }

        // Si está deslogueado, construye la matriz de Login
        return const LoginScreen();
      },
    );
  }
}
