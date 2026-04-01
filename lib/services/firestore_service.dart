import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Obtener o crear datos de un atleta específico por su UID
  Stream<DocumentSnapshot<Map<String, dynamic>>> getAthleteData(String uid) {
    return _db.collection('athletes').doc(uid).snapshots();
  }

  // Crear un perfil básico para un nuevo usuario social
  Future<void> ensureAthleteProfile(String uid, {String? nombre, String? email}) async {
    final doc = await _db.collection('athletes').doc(uid).get();
    if (!doc.exists) {
      await _db.collection('athletes').doc(uid).set({
        'full_name': nombre ?? 'Nuevo Atleta',
        'email': email ?? '',
        'gender': '',
        'birth_date': null,
        'sport': 'Voleibol', // Disciplina por defecto
        'rol': 'atleta',
        'fecha_registro': FieldValue.serverTimestamp(),
        'consentimiento_lopdp': true,
        'fecha_consentimiento': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getOrCreateAthleteData(String uid) async {
    final docRef = _db.collection('athletes').doc(uid);
    final doc = await docRef.get();
    if (!doc.exists) {
      await docRef.set({
        'full_name': 'Nuevo Atleta',
        'email': '',
        'gender': '',
        'birth_date': null,
        'sport': 'Voleibol',
        'rol': 'atleta',
        'fecha_registro': FieldValue.serverTimestamp(),
        'consentimiento_lopdp': true,
        'fecha_consentimiento': FieldValue.serverTimestamp(),
      });
      return await docRef.get();
    }
    return doc;
  }

  // Stream para leer los datos del primer atleta (Deprecando el uso estático)
  Stream<QuerySnapshot<Map<String, dynamic>>> getFirstAthleteData() {
    return _db.collection('athletes').limit(1).snapshots();
  }

  // Futura expansión para escribir datos
  Future<void> updateAthleteData(String athleteId, Map<String, dynamic> data) {
    return _db.collection('athletes').doc(athleteId).set(data, SetOptions(merge: true));
  }

  // Eliminar todos los datos del atleta de Firestore (ARCO - Cancelación)
  Future<void> deleteAthleteData(String uid) {
    return _db.collection('athletes').doc(uid).delete();
  }

  // Añade un registro de sesión de entrenamiento al historial del atleta
  Future<void> addTrainingSession(String athleteId, Map<String, dynamic> sessionData) {
    return _db
        .collection('athletes')
        .doc(athleteId)
        .collection('historial_entrenamientos')
        .add({
          ...sessionData,
          'fecha': FieldValue.serverTimestamp(),
        });
  }

  // Obtener posiciones del torneo ordenadas por posición (1, 2, 3...)
  Stream<QuerySnapshot<Map<String, dynamic>>> getTournamentStandings() {
    return _db.collection('posiciones_torneo').orderBy('puntos', descending: true).snapshots();
  }

  // Cargar datos de prueba para el torneo (Seed)
  Future<void> seedTournamentData() async {
    final batch = _db.batch();
    final collection = _db.collection('posiciones_torneo');

    final teams = [
      {'equipo': 'Titanes VC', 'puntos': 15, 'partidos_jugados': 5, 'posicion': 1},
      {'equipo': 'Raptors Volei', 'puntos': 12, 'partidos_jugados': 5, 'posicion': 2},
      {'equipo': 'Fénix Azul', 'puntos': 10, 'partidos_jugados': 5, 'posicion': 3},
      {'equipo': 'Linces del Norte', 'puntos': 7, 'partidos_jugados': 5, 'posicion': 4},
      {'equipo': 'Spartans Sport', 'puntos': 4, 'partidos_jugados': 5, 'posicion': 5},
    ];

    for (var team in teams) {
      final docRef = collection.doc();
      batch.set(docRef, team);
    }

    return batch.commit();
  }
}
