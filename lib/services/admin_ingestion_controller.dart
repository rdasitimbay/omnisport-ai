import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/ingestion_result.dart';
import 'bulk_ingestion_service.dart';

// Orquesta el flujo de ingesta masiva en dos fases:
//   1. Dry Run → valida sin escribir nada (BulkIngestionService).
//   2. Confirmación → Cloud Function persiste con Admin SDK.
// Art. 10 LOPDP: ningún dato sensible se escribe desde el cliente Flutter.
class AdminIngestionController {
  final BulkIngestionService _validator;
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  AdminIngestionController({
    BulkIngestionService? validator,
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _validator = validator ?? BulkIngestionService(),
        _functions = functions ?? FirebaseFunctions.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  // FASE 1: Simulación completa sin persistencia.
  // Incluye verificación de duplicados contra Firestore (solo lectura).
  Future<IngestionSummary> runDryRun(
    String csvString,
    String institutionId,
  ) {
    return _validator.validate(csvString, institutionId);
  }

  // FASE 2: Persistencia real delegada a Cloud Function.
  // La CF re-valida el CSV con Admin SDK y escribe de forma atómica.
  // Usa call<Map> para tipado seguro — compatible con cloud_functions ^6.1.0.
  Future<IngestionSummary> confirmIngestion(
    String csvString,
    String institutionId,
  ) async {
    try {
      final callable =
          _functions.httpsCallable('processBulkIngestion');
      final result = await callable.call<Map<Object?, Object?>>({
        'csv': csvString,
        'institutionId': institutionId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      return IngestionSummary(
        total:  (data['total']  as num?)?.toInt() ?? 0,
        valid:  (data['valid']  as num?)?.toInt() ?? 0,
        failed: (data['failed'] as num?)?.toInt() ?? 0,
        isDryRun: false,
        rows: [],
        executedAt: DateTime.now(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception('[CF ${e.code}] ${e.message}');
    }
  }

  // Lee el DNI desde /private (lectura de admin permitida por las reglas).
  // Art. 26 LOPDP: solo admins pueden acceder a la subcolección /private.
  Future<String> fetchDni(String athleteId) async {
    final doc = await _firestore
        .collection('athletes')
        .doc(athleteId)
        .collection('private')
        .doc('sensitive_data')
        .get();
    return doc.exists ? (doc.data()?['dni'] as String? ?? 'N/A') : 'N/A';
  }

  // Registra la visualización del DNI en audit_logs vía Cloud Function.
  // Art. 37 LOPDP: log inalterable; el cliente nunca escribe en audit_logs.
  Future<void> logDniReveal(String athleteId) async {
    try {
      final callable = _functions.httpsCallable('logSensitiveAccess');
      await callable.call<void>({
        'athleteId': athleteId,
        'action': 'unmask_dni',
      });
    } on FirebaseFunctionsException catch (e) {
      // Log de auditoría fallido no debe bloquear la UI — se registra en consola.
      // ignore: avoid_print
      print('[AdminIngestionController] logDniReveal error: ${e.code} — ${e.message}');
    }
  }
}
