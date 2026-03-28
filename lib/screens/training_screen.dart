import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../services/firestore_service.dart';

class TrainingScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;
  final String discipline;

  const TrainingScreen({
    Key? key,
    required this.athleteId,
    required this.athleteName,
    required this.discipline,
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
    _routineFuture = _aiService.generateTrainingRoutine(widget.athleteName, widget.discipline);
  }

  bool get _allCompleted => _completedExercises != null && _completedExercises!.every((e) => e);

  Future<void> _handleFinishSession(List exercises) async {
    if (!_allCompleted || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      await _firestoreService.addTrainingSession(widget.athleteId, {
        'disciplina': widget.discipline,
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
      backgroundColor: const Color(0xFFF8F9FA),
      body: FutureBuilder<Map<String, dynamic>>(
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
            return const Center(child: Text('No hay datos disponibles.'));
          }
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF003F87),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
          SizedBox(height: 24),
          Text(
            'Preparando Circuito...',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: $error'),
          TextButton(
            onPressed: () => setState(() {
              _routineFuture = _aiService.generateTrainingRoutine(widget.athleteName, widget.discipline);
              _completedExercises = null;
            }),
            child: const Text('Reintentar'),
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
                      'Rutina del Día',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_completedExercises!.where((e) => e).length}/${exercises.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Marca cada ejercicio al terminarlo para finalizar.', 
                     style: TextStyle(color: Colors.grey[600], fontSize: 14)),
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
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120.0,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF003F87),
      flexibleSpace: FlexibleSpaceBar(
        title: Text('${widget.athleteName} - ${widget.discipline}', 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
    );
  }

  Widget _buildExerciseCard(dynamic exercise, int index) {
    bool isDone = _completedExercises![index];
    
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isDone ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
          ],
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
                          color: isDone ? Colors.grey : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Reps: ${exercise['reps']}',
                        style: const TextStyle(color: Color(0xFF003F87), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        exercise['desc'] ?? '',
                        style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
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
    );
  }

  Widget _buildCheckButton(int index, bool isDone) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone ? Colors.green : Colors.grey.withOpacity(0.1),
        border: Border.all(color: isDone ? Colors.green : Colors.grey.withOpacity(0.3)),
      ),
      child: Icon(
        Icons.check, 
        size: 18, 
        color: isDone ? Colors.white : Colors.transparent
      ),
    );
  }

  Widget _buildFinishButton(List exercises) {
    bool ready = _allCompleted;
    
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: ready 
            ? [const Color(0xFF00B09B), const Color(0xFF96C93D)] // Green gradient
            : [const Color(0xFFBDC3C7), const Color(0xFF2C3E50)], // Grey/Inactive gradient
        ),
        boxShadow: ready ? [
          BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6)),
        ] : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: ready && !_isSaving ? () => _handleFinishSession(exercises) : null,
          child: Center(
            child: _isSaving 
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  'FINALIZAR SESIÓN',
                  style: TextStyle(
                    color: ready ? Colors.white : Colors.white60, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 16, 
                    letterSpacing: 1.2
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
