import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

class TablasScreen extends StatelessWidget {
  const TablasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Tabla de Posiciones', 
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003F87))),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF003F87)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestoreService.getTournamentStandings(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Error al cargar posiciones'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(firestoreService);
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: Colors.white,
      child: const Row(
        children: [
          SizedBox(width: 30, child: Text('Pos', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          Expanded(child: Text('Equipo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          SizedBox(width: 40, child: Text('PJ', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          SizedBox(width: 50, child: Text('Pts', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildTeamCard(Map<String, dynamic> data, int index) {
    Color positionColor = Colors.grey.shade400;
    if (index == 1) positionColor = const Color(0xFFFFD700); // Gold
    if (index == 2) positionColor = const Color(0xFFC0C0C0); // Silver
    if (index == 3) positionColor = const Color(0xFFCD7F32); // Bronze

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${data['posicion'] ?? index}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: index <= 3 ? positionColor : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: positionColor.withOpacity(0.2),
            child: Icon(Icons.shield, color: positionColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              data['equipo'] ?? 'Equipo Desconocido',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${data['partidos_jugados'] ?? 0}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${data['puntos'] ?? 0}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF003F87)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(FirestoreService firestoreService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('No hay datos del torneo aún', 
            style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => firestoreService.seedTournamentData(),
            icon: const Icon(Icons.refresh),
            label: const Text('Cargar Datos de Prueba'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003F87),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
