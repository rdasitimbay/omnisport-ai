import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'parent_dashboard_screen.dart';

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

        if (snapshot.hasData && snapshot.data != null) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('app_config').doc('global_settings').snapshots(),
            builder: (context, configSnapshot) {
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(snapshot.data!.uid).get(),
                builder: (context, docSnapshot) {
                  if (docSnapshot.connectionState == ConnectionState.waiting || !configSnapshot.hasData) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
                    );
                  }
                  
                  final isMaintenance = (configSnapshot.data?.data() as Map<String, dynamic>?)?['maintenance_mode'] ?? false;
                  String? role;
                  String? athleteDocId;

                  if (docSnapshot.hasData && docSnapshot.data!.exists) {
                    final userData = docSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                    role         = userData['role']         as String?;
                    athleteDocId = userData['athleteDocId'] as String?;

                    if (role == 'admin' && kIsWeb) {
                      return const AdminDashboardScreen(institutionId: 'inst_piloto_stresstest');
                    }
                    if (role == 'parent') {
                      return ParentDashboardScreen(parentUid: snapshot.data!.uid);
                    }
                  }

                  if (isMaintenance && role != 'admin') {
                    return Scaffold(
                      backgroundColor: const Color(0xFF001F3F),
                      body: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.build, size: 80, color: Colors.amberAccent),
                            const SizedBox(height: 20),
                            const Text('Servicio Temporalmente No Disponible',
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            const Text('Estamos realizando mejoras. Vuelve pronto.',
                                style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 30),
                            ElevatedButton(
                              onPressed: () => FirebaseAuth.instance.signOut(),
                              child: const Text('Cerrar Sesión'),
                            )
                          ],
                        ),
                      ),
                    );
                  }

                  // athleteDocId: ID del documento /athletes/{id} vinculado a este usuario.
                  // Si está disponible, el DashboardScreen carga el perfil correcto.
                  // Si no, el Dashboard muestra "Perfil no configurado" (cuenta pendiente de ingesta).
                  return DashboardScreen(
                    currentAthleteId: athleteDocId ?? snapshot.data!.uid,
                  );
                },
              );
            }
          );
        }

        // Si está deslogueado, construye la matriz de Login
        return const LoginScreen();
      },
    );
  }
}
