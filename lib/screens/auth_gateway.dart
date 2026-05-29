import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_mobile_dashboard_screen.dart';
import 'parent_dashboard_screen.dart';
import 'coach_dashboard_screen.dart';
import '../services/rbac_service.dart';


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
                  // Espera datos de user doc Y de config.
                  // Si configSnapshot tiene error (ej. permisos denegados), se continúa
                  // sin maintenance_mode para no bloquear a usuarios recién registrados.
                  if (docSnapshot.connectionState == ConnectionState.waiting ||
                      (!configSnapshot.hasData && !configSnapshot.hasError)) {
                    return const Scaffold(
                      backgroundColor: Color(0xFF001F3F),
                      body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
                    );
                  }
                  
                  // iOS fix: usar Map.from() para evitar crash con Map<Object?, Object?>
                  final configRaw = configSnapshot.data?.data();
                  final configData = configRaw != null ? Map<String, dynamic>.from(configRaw as Map) : <String, dynamic>{};
                  final isMaintenance = configData['maintenance_mode'] ?? false;
                  String? role;
                  String? athleteDocId;

                  if (docSnapshot.hasData && docSnapshot.data!.exists) {
                    final userRaw = docSnapshot.data!.data();
                    final userData = userRaw != null ? Map<String, dynamic>.from(userRaw as Map) : <String, dynamic>{};
                    // Normalizar rol: 'user' y vacío → 'athlete' (USR-ROL v2)
                    final rawRole = userData['role'] as String?;
                    role         = RbacService.normalize(rawRole);
                    athleteDocId = userData['athleteDocId'] as String?;
                    final isActive = userData['isActive'] ?? true;

                    if (!isActive) {
                      return Scaffold(
                        backgroundColor: const Color(0xFF001F3F),
                        body: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.block, size: 80, color: Colors.redAccent),
                              const SizedBox(height: 20),
                              const Text('Acceso Denegado',
                                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              const Text('Tu cuenta ha sido dada de baja o está inactiva.\nComunícate con administración.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70)),
                              const SizedBox(height: 30),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () => FirebaseAuth.instance.signOut(),
                                child: const Text('Volver al Login', style: TextStyle(color: Colors.white)),
                              )
                            ],
                          ),
                        ),
                      );
                    }

                    // RBAC USR-ROL: Admin
                    // Web → AdminDashboardScreen completo (backoffice)
                    // Móvil → AdminMobileDashboardScreen simplificado
                    if (role == RbacService.roleAdmin) {
                      return kIsWeb
                          ? const AdminDashboardScreen(institutionId: 'inst_piloto_stresstest')
                          : const AdminMobileDashboardScreen();
                    }
                    // RBAC USR-ROL: Padre de familia
                    // Acceso restringido a datos de sus tutorados (childrenIds en Firestore)
                    if (role == RbacService.roleParent) {
                      return ParentDashboardScreen(parentUid: snapshot.data!.uid);
                    }
                    // RBAC USR-ROL: Coach
                    // Filtro automático por institutionId/coachId en queries
                    if (role == RbacService.roleCoach) {
                      return CoachDashboardScreen(
                        coachUid: snapshot.data!.uid,
                        institutionId: userData['institutionId'] ?? 'inst_piloto_stresstest',
                      );
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
