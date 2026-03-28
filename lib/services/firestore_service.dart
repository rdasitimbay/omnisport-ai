import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream para leer los datos del primer atleta en la colección
  Stream<QuerySnapshot<Map<String, dynamic>>> getFirstAthleteData() {
    return _db.collection('atletas').limit(1).snapshots();
  }

  // Futura expansión para escribir datos
  Future<void> updateAthleteData(String athleteId, Map<String, dynamic> data) {
    return _db.collection('atletas').doc(athleteId).set(data, SetOptions(merge: true));
  }

  // Añade un registro de sesión de entrenamiento al historial del atleta
  Future<void> addTrainingSession(String athleteId, Map<String, dynamic> sessionData) {
    return _db
        .collection('atletas')
        .doc(athleteId)
        .collection('historial_entrenamientos')
        .add({
          ...sessionData,
          'fecha': FieldValue.serverTimestamp(),
        });
  }
}
