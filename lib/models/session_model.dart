import 'package:hive/hive.dart';

part 'session_model.g.dart';

@HiveType(typeId: 1)
class SessionModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String athleteId;

  @HiveField(2)
  final String sport;

  @HiveField(3)
  final int ejerciciosCompletados;

  @HiveField(4)
  final String atletaNombre;

  @HiveField(5)
  final String tipo;

  @HiveField(6)
  final DateTime fecha;

  SessionModel({
    required this.id,
    required this.athleteId,
    required this.sport,
    required this.ejerciciosCompletados,
    required this.atletaNombre,
    required this.tipo,
    required this.fecha,
  });

  Map<String, dynamic> toMap() {
    return {
      'sport': sport,
      'ejercicios_completados': ejerciciosCompletados,
      'atleta': atletaNombre,
      'tipo': tipo,
      // Nota: El timestamp del servidor se setea en firestore_service.dart al sincronizar
    };
  }
}
