import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import 'training_screen.dart';
import 'profile_screen.dart';
import 'tablas_screen.dart';
import 'qr_generator_screen.dart';
import 'qr_scanner_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DashboardScreen extends StatefulWidget {
  final String currentAthleteId;

  const DashboardScreen({Key? key, required this.currentAthleteId})
    : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getAthleteData(widget.currentAthleteId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text(
                "Error al cargar data de athletes",
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          // El perfil de atleta solo puede crearse desde el backoffice (admin).
          // Art. 26 LOPDP: la cuenta debe pasar por el proceso de consentimiento
          // del tutor antes de existir en Firestore.
          return Scaffold(
            backgroundColor: const Color(0xFF0A192F),
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF00E5FF).withOpacity(0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off_outlined,
                              size: 64,
                              color: Color(0xFF00E5FF),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Perfil no configurado',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Tu cuenta requiere el consentimiento de tu tutor legal (LOPDP).\nContacta al administrador de tu institución.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final athleteDoc = snapshot.data!;
        final athleteData = athleteDoc.data()!;
        final String nombre =
            athleteData['full_name'] ??
            athleteData['nombre_completo'] ??
            athleteData['nombre'] ??
            'Desconocido';
        final String sport =
            athleteData['sport'] ??
            athleteData['disciplina'] ??
            'Sin disciplina';

        return Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text(
              'OMNISPORT-AI',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white70),
                onPressed: () => FirebaseAuth.instance.signOut(),
              ),
            ],
          ),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWelcomeCard(
                        nombre,
                        sport,
                        athleteData['photoBase64'],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "Acciones Rápidas",
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildQuickActions(athleteDoc.id, nombre, sport),
                      const SizedBox(height: 24),
                      const Text(
                        "Staff Tools (Demo)",
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildStaffActions(),
                      const SizedBox(height: 24),
                      const Text(
                        "Rendimiento",
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildWeeklyPerformance(athleteDoc.id),
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: _buildGlassBottomBar(
            context,
            athleteDoc.id,
            nombre,
            sport,
            athleteData,
          ),
        );
      },
    );
  }

  Widget _buildWelcomeCard(String nombre, String sport, String? photoBase64) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // Avatar con Glow
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.2),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.white24,
                  backgroundImage:
                      (photoBase64 != null && photoBase64.isNotEmpty)
                      ? MemoryImage(base64Decode(photoBase64))
                      : null,
                  child: photoBase64 == null
                      ? const Icon(
                          CupertinoIcons.person_fill,
                          color: Colors.white,
                          size: 35,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Bienvenido,",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sports_volleyball,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            sport,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(String athleteId, String nombre, String sport) {
    return Row(
      children: [
        Expanded(
          child: _actionCard(
            "Entreno",
            "Sesión IA",
            CupertinoIcons.play_circle_fill,
            const Color(0xFF00E5FF), // Cyan para icon
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TrainingScreen(
                    athleteId: athleteId,
                    athleteName: nombre,
                    sport: sport,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionCard(
            "Acceso",
            "Pase QR",
            CupertinoIcons.qrcode,
            Colors.purpleAccent,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const QrGeneratorScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionCard(
            "Torneos",
            "Eventos",
            Icons.emoji_events,
            const Color(0xFFFFB300), // Naranja para icon
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TablasScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStaffActions() {
    return Row(
      children: [
        Expanded(
          child: _actionCard(
            "Zero Trust",
            "Escáner Staff",
            CupertinoIcons.barcode_viewfinder,
            Colors.greenAccent,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const QrScannerScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Container(), // Spacer to visually un-stretch if needed, or add future tools
        ),
        const SizedBox(width: 8),
        Expanded(child: Container()),
      ],
    );
  }

  Widget _actionCard(
    String title,
    String subtitle,
    IconData icon,
    Color iconColor, {
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 32, color: iconColor),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyPerformance(String athleteId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('athletes')
          .doc(athleteId)
          .collection('historial_entrenamientos')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      CupertinoIcons.flame,
                      size: 48,
                      color: Colors.white30,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Aún no hay registros",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "El primer paso es empezar. ¡Ve a la sección Entreno y comienza a sudar la camiseta!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Rendimiento Semanal",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Icon(
                        CupertinoIcons.graph_square,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: const LinearProgressIndicator(
                      value: 0.8,
                      minHeight: 8,
                      backgroundColor: Colors.white10,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _metricBlock("${snapshot.data!.docs.length}", "Sesiones"),
                      _metricBlock("3.2k", "Calorías"),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metricBlock(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white60,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassBottomBar(
    BuildContext context,
    String athleteId,
    String nombre,
    String sport,
    Map<String, dynamic> athleteData,
  ) {
    return Container(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 20,
            sigmaY: 20,
          ), // Aumentamos un poco el blur
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(
                0.03,
              ), // Menos opacidad para el 'cristal'
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.2),
                  width: 0.5,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: 0,
              backgroundColor: Colors.transparent, // Transparencia absoluta
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              iconSize: 28, // Mayor presencia visual en el cristal
              selectedItemColor: const Color(0xFF00E5FF), // Cian Eléctrico
              unselectedItemColor: Colors.white.withOpacity(
                0.6,
              ), // Ajuste a 0.6 para no verse apagados
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.6),
              ),
              onTap: (index) {
                if (index == 0) return;
                if (index == 1) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TrainingScreen(
                        athleteId: athleteId,
                        athleteName: nombre,
                        sport: sport,
                      ),
                    ),
                  );
                } else if (index == 2) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileScreen(
                        athleteId: athleteId,
                        athleteName: nombre,
                        photoBase64: athleteData['photoBase64'],
                      ),
                    ),
                  );
                }
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.house),
                  activeIcon: Icon(
                    CupertinoIcons.house_fill,
                    shadows: [Shadow(color: Color(0xFF00E5FF), blurRadius: 12)],
                  ),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.bolt),
                  activeIcon: Icon(
                    CupertinoIcons.bolt_fill,
                    shadows: [Shadow(color: Color(0xFF00E5FF), blurRadius: 12)],
                  ),
                  label: 'Rutina',
                ),
                BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.person),
                  activeIcon: Icon(
                    CupertinoIcons.person_fill,
                    shadows: [Shadow(color: Color(0xFF00E5FF), blurRadius: 12)],
                  ),
                  label: 'Perfil',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
