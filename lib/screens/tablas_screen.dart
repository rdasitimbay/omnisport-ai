import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

class TablasScreen extends StatelessWidget {
  const TablasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Tabla de Posiciones', 
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.white.withOpacity(0.05)),
          ),
        ),
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
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildHeader(),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: firestoreService.getTournamentStandings(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text('Error al cargar posiciones', style: TextStyle(color: Colors.white70)));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return _buildEmptyState(firestoreService);
                    }

                    final docs = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        return _buildTeamCard(data, index + 1);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 35, child: Text('Pos', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white60, fontSize: 12))),
          Expanded(child: Text('Equipo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white60, fontSize: 12))),
          SizedBox(width: 40, child: Text('PJ', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white60, fontSize: 12))),
          SizedBox(width: 50, child: Text('Pts', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white60, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildTeamCard(Map<String, dynamic> data, int index) {
    Color positionColor = Colors.white70;
    if (index == 1) positionColor = const Color(0xFFFFD700); // Gold
    if (index == 2) positionColor = const Color(0xFFC0C0C0); // Silver
    if (index == 3) positionColor = const Color(0xFFCD7F32); // Bronze

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 35,
                  child: Text(
                    '${data['posicion'] ?? index}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: positionColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: positionColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(CupertinoIcons.shield_fill, color: positionColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data['equipo'] ?? 'Equipo Desconocido',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${data['partidos_jugados'] ?? 0}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${data['puntos'] ?? 0}',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: index == 1 ? const Color(0xFF00E5FF) : Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(FirestoreService firestoreService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined, size: 80, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text('No hay datos del torneo aún', 
            style: TextStyle(color: Colors.white60, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => firestoreService.seedTournamentData(),
            icon: const Icon(Icons.refresh),
            label: const Text('Cargar Datos de Prueba'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ).copyWith(
               side: WidgetStateProperty.all(BorderSide(color: Colors.white.withOpacity(0.2)))
            ),
          ),
        ],
      ),
    );
  }
}
