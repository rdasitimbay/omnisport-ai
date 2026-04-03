import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/ai_service.dart';
import '../services/firestore_service.dart';

class TrainingScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;
  final String sport;

  const TrainingScreen({
    Key? key,
    required this.athleteId,
    required this.athleteName,
    required this.sport,
  }) : super(key: key);

  @override
  _TrainingScreenState createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  final AIService _aiService = AIService();
  final FirestoreService _firestoreService = FirestoreService();
  
  late Future<Map<String, dynamic>> _routineFuture;
  List<bool>? _completedExercises;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _routineFuture = _aiService.generateTrainingRoutine(widget.athleteName, widget.sport);
  }

  bool get _allCompleted => _completedExercises != null && _completedExercises!.every((e) => e);

  Future<void> _handleFinishSession(List exercises) async {
    if (!_allCompleted || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      await _firestoreService.addTrainingSession(widget.athleteId, {
        'sport': widget.sport,
        'ejercicios_completados': exercises.length,
        'atleta': widget.athleteName,
        'tipo': 'IA Generated',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Entrenamiento guardado con éxito! 🏆'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
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
        child: FutureBuilder<Map<String, dynamic>>(
          future: _routineFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState();
            } else if (snapshot.hasError) {
              return _buildErrorState(snapshot.error.toString());
            } else if (snapshot.hasData) {
              final List exercises = snapshot.data!['exercises'] ?? [];
              _completedExercises ??= List.filled(exercises.length, false);
              return _buildMainContent(exercises);
            } else {
              return const Center(child: Text('No hay datos disponibles.', style: TextStyle(color: Colors.white)));
            }
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
          const SizedBox(height: 24),
          Text(
            'Generando Rutina IA...',
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.white70),
          const SizedBox(height: 16),
          Text('Error: $error', style: const TextStyle(color: Colors.white70)),
          TextButton(
            onPressed: () => setState(() {
              _routineFuture = _aiService.generateTrainingRoutine(widget.athleteName, widget.sport);
              _completedExercises = null;
            }),
            child: const Text('Reintentar', style: TextStyle(color: Color(0xFF00E5FF))),
          )
        ],
      ),
    );
  }

  Widget _buildMainContent(List exercises) {
    return CustomScrollView(
      slivers: [
        _buildSliverAppBar(),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tu Rutina del Día',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_completedExercises!.where((e) => e).length}/${exercises.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Marca cada ejercicio al finalizar para completar la sesión.', 
                     style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildExerciseCard(exercises[index], index),
              childCount: exercises.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: _buildFinishButton(exercises),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 60)),
      ],
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120.0,
      pinned: true,
      elevation: 0,
      stretch: true,
      backgroundColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: FlexibleSpaceBar(
            title: Text('${widget.sport} Intensity', 
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
            centerTitle: true,
            background: Container(
              color: Colors.white.withOpacity(0.05),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(dynamic exercise, int index) {
    bool isDone = _completedExercises![index];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: isDone ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDone ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => setState(() => _completedExercises![index] = !isDone),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise['name'] ?? 'Ejercicio',
                            style: TextStyle(
                              fontSize: 18, 
                              fontWeight: FontWeight.bold,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                              color: isDone ? Colors.white38 : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Semanas: ${exercise['reps']}',
                            style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            exercise['desc'] ?? '',
                            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6), height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildCheckButton(index, isDone),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckButton(int index, bool isDone) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.10),
        border: Border.all(color: isDone ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.3), width: 1.5),
        boxShadow: isDone ? [
          BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.3), blurRadius: 8, spreadRadius: 1),
        ] : [],
      ),
      child: Icon(
        Icons.check, 
        size: 20, 
        color: isDone ? Colors.black87 : Colors.transparent
      ),
    );
  }

  Widget _buildFinishButton(List exercises) {
    bool ready = _allCompleted;
    
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: ready 
            ? [const Color(0xFF00E5FF), const Color(0xFF00BFA5)] // Cyan gradient
            : [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)], // Glassy inactive
        ),
        boxShadow: ready ? [
          BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 6)),
        ] : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: ready && !_isSaving ? () => _handleFinishSession(exercises) : null,
          child: Center(
            child: _isSaving 
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                   ready ? 'FINALIZAR ENTRENAMIENTO' : 'COMPLETA TODOS LOS EJERCICIOS',
                  style: TextStyle(
                    color: ready ? Colors.black87 : Colors.white38, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 14, 
                    letterSpacing: 1.5
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
