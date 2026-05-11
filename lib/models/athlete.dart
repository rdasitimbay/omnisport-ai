import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'athlete.g.dart';

@HiveType(typeId: 0)
class Athlete {
  @HiveField(0)
  final String uid;
  
  @HiveField(1)
  final String fullName;
  
  @HiveField(2)
  final String photoUrl;
  
  @HiveField(3)
  final String teamOrCategory;
  
  @HiveField(4)
  final String paymentStatus;
  
  @HiveField(5)
  final String status;
  
  @HiveField(6)
  final String representativeUid;
  
  @HiveField(7)
  final DateTime? lastMedicalReview;

  Athlete({
    required this.uid,
    required this.fullName,
    required this.photoUrl,
    required this.teamOrCategory,
    required this.paymentStatus,
    required this.status,
    required this.representativeUid,
    this.lastMedicalReview,
  });

  factory Athlete.fromMap(String uid, Map<String, dynamic> data) {
    return Athlete(
      uid: uid,
      // Usamos 'full_name' porque así está en tu captura de Firestore
      fullName: data['full_name'] ?? 'Atleta Nuevo',
      photoUrl: data['photoUrl'] ?? '',
      teamOrCategory: data['teamOrCategory'] ?? 'Sin Categoría',
      paymentStatus: data['paymentStatus'] ?? 'Al Día',
      status: data['status'] ?? 'Acceso Autorizado',
      representativeUid: data['representativeUid'] ?? '',
      lastMedicalReview: data['lastMedicalReview'] != null
          ? (data['lastMedicalReview'] as Timestamp).toDate()
          : null,
    );
  }
}
