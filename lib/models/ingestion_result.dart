enum IngestionStatus { valid, error }

class IngestionRowResult {
  final int rowNumber;
  final String name;
  final IngestionStatus status;
  final String message;

  const IngestionRowResult({
    required this.rowNumber,
    required this.name,
    required this.status,
    required this.message,
  });
}

class IngestionSummary {
  final int total;
  final int valid;
  final int failed;
  final bool isDryRun;
  final List<IngestionRowResult> rows;
  final DateTime executedAt;

  const IngestionSummary({
    required this.total,
    required this.valid,
    required this.failed,
    required this.isDryRun,
    required this.rows,
    required this.executedAt,
  });

  List<IngestionRowResult> get errors =>
      rows.where((r) => r.status == IngestionStatus.error).toList();

  String toReportString(String institutionId) {
    final mode = isDryRun
        ? 'SIMULACIÓN DRY RUN (Base de datos NO alterada)'
        : 'EJECUCIÓN EN PRODUCCIÓN (Datos persistidos vía Cloud Function)';
    final detail = errors.isEmpty
        ? 'Ninguna incongruencia sistémica o LOPDP detectada.'
        : errors
            .map((e) => 'Fila ${e.rowNumber} (${e.name}): ${e.message}')
            .join('\n');

    return '''
=== AUDITORÍA FORENSE DE INGESTA ===
Fecha Ejecución : ${executedAt.toIso8601String()}
Institución Base: $institutionId
Modo del Sistema: $mode

[Resumen Analítico]
  Registros Procesados : $total
  Aprobados (Exitosos) : $valid
  Rechazados (Errores) : $failed

[Detalle de Resultados Forenses]
$detail
====================================
''';
  }
}
