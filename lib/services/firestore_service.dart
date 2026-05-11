import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ─── TOKEN ────────────────────────────────────────────────────────────────

  // Fuerza la renovación del JWT para activar Custom Claims actualizados.
  // Llamar obligatoriamente después de signConsent() o setUserRole() en CF.
  // Art. 10 LOPDP: sin este paso, consent_signed y role no entran en vigor.
  Future<void> refreshToken() async {
    await _auth.currentUser?.getIdToken(true);
  }

  // ─── LECTURA DE ATLETAS ───────────────────────────────────────────────────

  // Stream del documento público del atleta. Las reglas Firestore garantizan
  // que solo el owner, su coach institucional o un admin reciban datos.
  Stream<DocumentSnapshot<Map<String, dynamic>>> getAthleteData(String uid) {
    return _db.collection('athletes').doc(uid).snapshots();
  }

  // ─── ESCRITURA DE ATLETAS ─────────────────────────────────────────────────

  // Actualización de campos no sensibles del perfil propio del atleta.
  // Usa update() (no set) para que diff() en isValidAthleteUpdate() solo vea
  // los campos enviados. Si el caller intenta pasar 'rol' o 'institutionId',
  // Firestore rechaza la operación en la capa de reglas, no solo aquí.
  Future<void> updateAthleteData(
    String athleteId,
    Map<String, dynamic> data,
  ) {
    data['updatedAt'] = FieldValue.serverTimestamp();
    return _db.collection('athletes').doc(athleteId).update(data);
  }

  // Upsert jerárquico de perfil completo (operación de admin — ingesta masiva
  // o backoffice). La creación de documentos de atleta nunca ocurre desde el
  // cliente de un atleta; las reglas lo rechazan con allow create: if isAdmin().
  Future<void> upsertAthleteProfile(
    String uid,
    Map<String, dynamic> rootData,
    Map<String, dynamic> sportData,
  ) async {
    final batch = _db.batch();

    final rootRef = _db.collection('athletes').doc(uid);
    rootData['updatedAt'] = FieldValue.serverTimestamp();
    batch.set(rootRef, rootData, SetOptions(merge: true));

    if (sportData.containsKey('sport_type')) {
      final sportId = sportData['sport_type'].toString().toLowerCase();
      final sportRef = rootRef.collection('sport_details').doc(sportId);
      sportData['updatedAt'] = FieldValue.serverTimestamp();
      batch.set(sportRef, sportData, SetOptions(merge: true));
    }

    await batch.commit();
  }

  // ─── ELIMINACIÓN (ARCO — DERECHO AL OLVIDO) ───────────────────────────────

  // Art. 16 LOPDP — Derecho al olvido: el cliente NO puede acceder a
  // la subcolección /private directamente (solo admin por reglas).
  // La eliminación en cascada se delega a una Cloud Function que usa
  // Admin SDK y bypasea las reglas, garantizando borrado completo y auditado.
  Future<void> requestAthleteErasure(String uid) async {
    final callable = _functions.httpsCallable('requestAthleteErasure');
    await callable.call({'uid': uid});
  }

  // ─── HISTORIAL DE ENTRENAMIENTOS ──────────────────────────────────────────

  // Añade una sesión al historial del atleta.
  // Las reglas Firestore validan que el caller sea admin o coach de la
  // misma institución del atleta (athleteInstitution() en las reglas).
  Future<void> addTrainingSession(
    String athleteId,
    Map<String, dynamic> sessionData,
  ) {
    return _db
        .collection('athletes')
        .doc(athleteId)
        .collection('historial_entrenamientos')
        .add({
          ...sessionData,
          'fecha': FieldValue.serverTimestamp(),
        });
  }

  // ─── TORNEOS ──────────────────────────────────────────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> getTournamentStandings() {
    return _db
        .collection('tournaments')
        .orderBy('puntos', descending: true)
        .snapshots();
  }
}
