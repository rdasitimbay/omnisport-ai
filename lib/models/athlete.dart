import 'package:cloud_firestore/cloud_firestore.dart';

class Athlete {
  final String uid;
  final String fullName;
  final String photoUrl;
  final String teamOrCategory;
  final String paymentStatus;
  final String status;
  final String representativeUid;
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
