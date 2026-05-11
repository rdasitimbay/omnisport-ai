import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import '../models/ingestion_result.dart';

// Validador puro: nunca escribe en Firestore.
// La persistencia es responsabilidad de AdminIngestionController vía Cloud Function.
class BulkIngestionService {
  final FirebaseFirestore _firestore;

  BulkIngestionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // Valida el CSV y verifica duplicados en Firestore (solo lectura).
  // Art. 10 LOPDP: el cliente no persiste datos sensibles directamente.
  Future<IngestionSummary> validate(
    String csvString,
    String institutionId, {
    bool forceOrder = false,
  }) async {
    String cleanCsv = csvString
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('﻿', '');
    String headerLine = cleanCsv.split('\n').first.toLowerCase().trim();

    if (!forceOrder) {
      if (!headerLine.contains('full_name') ||
          !headerLine.contains('dni') ||
          !headerLine.contains('consent_date')) {
        String hexDebug = headerLine.codeUnits
            .map((u) => u.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        return _singleErrorSummary(
          '[CABECERA INVÁLIDA] Faltan columnas requeridas: full_name, dni, consent_date.\n'
          'Cabecera vista: "$headerLine"\nHex: $hexDebug',
        );
      }
    }

    String separator = (headerLine.contains(';') &&
            headerLine.split(';').length > headerLine.split(',').length)
        ? ';'
        : ',';

    List<List<dynamic>> csvRows =
        CsvToListConverter(eol: '\n', fieldDelimiter: separator)
            .convert(cleanCsv);

    if (csvRows.isEmpty) {
      return _singleErrorSummary(
          'El archivo está vacío o el separador no fue reconocido.');
    }

    List<String> headers = csvRows.first
        .map((e) =>
            e.toString().toLowerCase().replaceAll('﻿', '').trim())
        .toList();

    int nameIndex    = headers.indexWhere((h) => h.contains('full_name') || h.contains('nombre'));
    int dniIndex     = headers.indexWhere((h) => h.contains('dni'));
    int emailIndex   = headers.indexWhere((h) => h.contains('email') || h.contains('correo'));
    int phoneIndex   = headers.indexWhere((h) => h.contains('phone') || h.contains('telefono'));
    int teamIndex    = headers.indexWhere((h) => h.contains('team') || h.contains('categor'));
    int consentIndex = headers.indexWhere((h) => h.contains('consent_date') || h.contains('consentimiento'));

    if (!forceOrder && (dniIndex == -1 || nameIndex == -1 || consentIndex == -1)) {
      return _singleErrorSummary(
          '[ÍNDICES PERDIDOS] Columnas detectadas: $headers');
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    final dateRegex  = RegExp(r'^\d{4}-\d{2}-\d{2}$');

    int total   = 0;
    int success = 0;
    int failed  = 0;
    final rows  = <IngestionRowResult>[];

    for (int i = 1; i < csvRows.length; i++) {
      final row = csvRows[i];
      if (row.isEmpty || row.join('').trim().isEmpty) continue;
      total++;

      final name        = _cell(row, nameIndex);
      final dni         = _cell(row, dniIndex);
      final email       = _cell(row, emailIndex);
      final consentDate = _cell(row, consentIndex);
      final team        = teamIndex >= 0 ? _cell(row, teamIndex) : 'Sin Categoría';

      // LOPDP Art. 26: consentimiento del tutor es campo obligatorio.
      if (consentDate.isEmpty) {
        failed++;
        rows.add(_errorRow(i, name, '[ERROR CRÍTICO LOPDP] Consentimiento no proporcionado.'));
        continue;
      }
      if (!dateRegex.hasMatch(consentDate)) {
        failed++;
        rows.add(_errorRow(i, name, '[ERROR FORMATO] Fecha "$consentDate" no cumple YYYY-MM-DD.'));
        continue;
      }
      if (dni.isEmpty) {
        failed++;
        rows.add(_errorRow(i, name, '[ERROR DATO] DNI vacío.'));
        continue;
      }
      if (email.isNotEmpty && !emailRegex.hasMatch(email)) {
        failed++;
        rows.add(_errorRow(i, name, '[ERROR FORMATO] Email inválido: "$email".'));
        continue;
      }

      // Verificación de unicidad forense (solo lectura — Art. 10 LOPDP).
      try {
        final existing = await _firestore
            .collectionGroup('sensitive_data')
            .where('dni', isEqualTo: dni)
            .get();
        if (existing.docs.isNotEmpty) {
          failed++;
          rows.add(_errorRow(i, name, '[ERROR DUPLICIDAD] DNI "$dni" ya registrado.'));
          continue;
        }
      } catch (e) {
        failed++;
        rows.add(_errorRow(i, name, '[ERROR DB] Verificación de duplicado fallida: $e'));
        continue;
      }

      success++;
      rows.add(IngestionRowResult(
        rowNumber: i + 1,
        name: name,
        status: IngestionStatus.valid,
        message: 'OK — DNI: ${_maskDni(dni)}, Equipo: $team, Consentimiento: $consentDate',
      ));
    }

    return IngestionSummary(
      total: total,
      valid: success,
      failed: failed,
      isDryRun: true,
      rows: rows,
      executedAt: DateTime.now(),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _cell(List<dynamic> row, int index) =>
      (index >= 0 && index < row.length) ? row[index].toString().trim() : '';

  String _maskDni(String dni) =>
      dni.length > 4
          ? '${'•' * (dni.length - 4)}${dni.substring(dni.length - 4)}'
          : '••••';

  IngestionRowResult _errorRow(int i, String name, String message) =>
      IngestionRowResult(
        rowNumber: i + 1,
        name: name,
        status: IngestionStatus.error,
        message: message,
      );

  IngestionSummary _singleErrorSummary(String message) => IngestionSummary(
        total: 0,
        valid: 0,
        failed: 1,
        isDryRun: true,
        rows: [
          IngestionRowResult(
            rowNumber: 0,
            name: '—',
            status: IngestionStatus.error,
            message: message,
          )
        ],
        executedAt: DateTime.now(),
      );
}
