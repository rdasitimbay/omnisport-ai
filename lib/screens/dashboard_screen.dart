import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import 'training_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String currentAthleteId; // Por ahora, pasamos el ID estáticamente o de auth

  const DashboardScreen({Key? key, required this.currentAthleteId}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // background color from HTML
      appBar: AppBar(
        title: const Text('OmniSport-AI', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestoreService.getFirstAthleteData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Error al leer la colección 'atletas'"));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Atleta no encontrado. La colección 'atletas' está vacía."));
          }

          var athleteData = snapshot.data!.docs.first.data();
          String nombre = athleteData['nombre_completo'] ?? athleteData['nombre'] ?? 'Desconocido';
          String disciplina = athleteData['disciplina'] ?? 'Sin disciplina';

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWelcomeCard(nombre, disciplina),
                  const SizedBox(height: 24),
                  _buildQuickActions(snapshot.data!.docs.first.id, nombre, disciplina),
                  const SizedBox(height: 24),
                  _buildWeeklyPerformance(),
                ],
            ),
          ),
        );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: 'Entrenamiento'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard(String nombre, String disciplina) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF003F87), // primary container equivalent
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Estado Actual", style: TextStyle(color: Colors.white70, letterSpacing: 1.5, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            "Hola, $nombre! 👋",
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sports_volleyball, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(disciplina, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(String athleteId, String nombre, String disciplina) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TrainingScreen(
                    athleteId: athleteId,
                    athleteName: nombre,
                    discipline: disciplina,
                  ),
                ),
              );
            },
            child: _actionCard("Iniciar Entrenamiento", "Sesión IA", Icons.play_circle_fill, Colors.blue),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _actionCard("Ver Torneo", "Próximo Evento", Icons.emoji_events, Colors.orange),
        ),
      ],
    );
  }

  Widget _actionCard(String title, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildWeeklyPerformance() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Rendimiento Semanal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          const LinearProgressIndicator(value: 0.8, backgroundColor: Color(0xFFEEEEEE), color: Colors.blue),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricBlock("12.4h", "Tiempo"),
              _metricBlock("3.2k", "Calorías"),
            ],
          )
        ],
      ),
    );
  }

  Widget _metricBlock(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, letterSpacing: 1.2)),
      ],
    );
  }
}
