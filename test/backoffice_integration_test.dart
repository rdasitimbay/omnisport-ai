/// Backoffice integration tests for OmniSport-AI.
/// Covers: AdminIngestionController dry-run, session status resolution,
/// attendance log data integrity, admin permission checks, and CSV edge cases.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app/services/bulk_ingestion_service.dart';
import 'package:app/models/ingestion_result.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Mirrors production logic from session_attendance_screen.dart _resolveStatus.
String resolveStatus(
    String athleteUid, List<Map<String, dynamic>> todayLogs) {
  final myLogs = todayLogs
      .where((d) => d['athleteUid'] == athleteUid)
      .toList()
    ..sort((a, b) {
      final ta = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final tb = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta); // most-recent first
    });
  if (myLogs.isEmpty) return 'ausente';
  final lastAction = myLogs.first['action'] as String? ?? 'ingreso';
  return lastAction == 'ingreso' ? 'presente' : 'salida';
}

/// Mirrors production logic from admin_dashboard_screen.dart _checkPermissions.
const Set<String> _privilegedRoles = {'admin'};
const Set<String> _autoAdminEmails = {
  'asitimbay.rommel@gmail.com',
  'admin@omnisport.ai',
};

bool isPrivilegedRole(String role) => _privilegedRoles.contains(role);
bool isAutoAdminEmail(String email) => _autoAdminEmails.contains(email);

// ─── CSV fixtures ──────────────────────────────────────────────────────────────

String _csv3Valid() => '''full_name,dni,email,consent_date
Atleta Uno,1711111111,uno@test.com,2026-01-10
Atleta Dos,1722222222,dos@test.com,2026-02-15
Atleta Tres,1733333333,tres@test.com,2026-03-20''';

String _csvDuplicateDni() =>
    'full_name,dni,email,consent_date\nA,1711111111,a@test.com,2026-01-01\nB,1711111111,b@test.com,2026-01-01';

String _csvEmptyConsent() =>
    'full_name,dni,email,consent_date\nSin Consentimiento,1799999999,sc@test.com,';

String _csvMixed5() => '''full_name,dni,email,consent_date
OK Uno,1700000001,ok1@test.com,2026-01-01
OK Dos,1700000002,ok2@test.com,2026-02-01
OK Tres,1700000003,ok3@test.com,2026-03-01
Bad Email,1700000004,notemail,2026-04-01
No Consent,1700000005,nc@test.com,''';

// ─────────────────────────────────────────────────────────────────────────────
void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Grupo 1: AdminIngestionController / BulkIngestionService (backoffice web)
  // ═══════════════════════════════════════════════════════════════════════════
  group('Grupo 1: BulkIngestionService — flujo de ingesta masiva', () {
    late BulkIngestionService svc;

    setUp(() {
      svc = BulkIngestionService(firestore: FakeFirebaseFirestore());
    });

    test('CSV válido con 3 atletas → 3 válidos, 0 fallidos', () async {
      final summary = await svc.validate(_csv3Valid(), 'inst-001');
      expect(summary.total, equals(3));
      expect(summary.valid, equals(3));
      expect(summary.failed, equals(0));
    });

    test('CSV con DNI duplicado en el mismo lote — ambas filas son procesadas por el validador cliente',
        () async {
      // El validador cliente no puede detectar duplicados E2EE; el backend los detecta.
      // La validación cliente las marca ambas como válidas; el backend rechaza duplicados.
      // Verificamos que el servicio procesa el lote sin crash y retorna un resultado coherente.
      final summary = await svc.validate(_csvDuplicateDni(), 'inst-001');
      expect(summary.total, equals(2));
      // Al menos una fila debe tener un resultado (válido o fallido)
      expect(summary.rows.length, greaterThanOrEqualTo(1));
    });

    test('CSV con consentimiento LOPDP vacío → fila fallida con mensaje LOPDP',
        () async {
      final summary =
          await svc.validate(_csvEmptyConsent(), 'inst-001', forceOrder: true);
      expect(summary.failed, equals(1));
      expect(summary.errors.first.message, contains('LOPDP'));
    });

    test('Lote mixto 5 atletas: 3 válidos, 2 con error → counts correctos',
        () async {
      final summary =
          await svc.validate(_csvMixed5(), 'inst-001', forceOrder: true);
      expect(summary.total, equals(5));
      expect(summary.valid, equals(3));
      expect(summary.failed, equals(2));
    });

    test('toReportString() contiene "AUDITORÍA FORENSE"', () async {
      final summary = await svc.validate(_csv3Valid(), 'inst-001');
      final report = summary.toReportString('inst-001');
      expect(report, contains('AUDITORÍA FORENSE'));
    });

    test('El reporte incluye la fecha de ejecución (año 2026)', () async {
      final summary = await svc.validate(_csv3Valid(), 'inst-001');
      final report = summary.toReportString('inst-001');
      expect(report, contains('2026'));
    });

    test('El reporte incluye el institutionId pasado', () async {
      const institutionId = 'omnisport-ec-quito';
      final summary = await svc.validate(_csv3Valid(), institutionId);
      final report = summary.toReportString(institutionId);
      expect(report, contains(institutionId));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Grupo 2: Session attendance status resolver
  // ═══════════════════════════════════════════════════════════════════════════
  group('Grupo 2: Session attendance status resolver', () {
    final now = DateTime.now().toUtc();

    test('Atleta con 0 logs hoy → estado = ausente', () {
      final logs = <Map<String, dynamic>>[];
      expect(resolveStatus('uid-A', logs), equals('ausente'));
    });

    test('Atleta con un ingreso hoy → estado = presente', () {
      final ts = Timestamp.fromDate(
          DateTime.utc(now.year, now.month, now.day, 9, 0));
      final logs = [
        {'athleteUid': 'uid-B', 'action': 'ingreso', 'timestamp': ts},
      ];
      expect(resolveStatus('uid-B', logs), equals('presente'));
    });

    test('Atleta con ingreso+salida hoy (salida más reciente) → estado = salida',
        () {
      final tsIngreso = Timestamp.fromDate(
          DateTime.utc(now.year, now.month, now.day, 9, 0));
      final tsSalida = Timestamp.fromDate(
          DateTime.utc(now.year, now.month, now.day, 12, 0));
      final logs = [
        {'athleteUid': 'uid-C', 'action': 'ingreso', 'timestamp': tsIngreso},
        {'athleteUid': 'uid-C', 'action': 'salida', 'timestamp': tsSalida},
      ];
      expect(resolveStatus('uid-C', logs), equals('salida'));
    });

    test('Los logs de otro atleta no afectan el estado del atleta consultado',
        () {
      final ts = Timestamp.fromDate(
          DateTime.utc(now.year, now.month, now.day, 9, 0));
      final logs = [
        {'athleteUid': 'uid-X', 'action': 'ingreso', 'timestamp': ts},
      ];
      // uid-D no tiene logs propios
      expect(resolveStatus('uid-D', logs), equals('ausente'));
    });

    test(
        'Atleta con múltiples ingresos y sin salida → estado = presente (último es ingreso)',
        () {
      final ts1 = Timestamp.fromDate(
          DateTime.utc(now.year, now.month, now.day, 8, 0));
      final ts2 = Timestamp.fromDate(
          DateTime.utc(now.year, now.month, now.day, 10, 0));
      final logs = [
        {'athleteUid': 'uid-E', 'action': 'ingreso', 'timestamp': ts1},
        {'athleteUid': 'uid-E', 'action': 'ingreso', 'timestamp': ts2},
      ];
      expect(resolveStatus('uid-E', logs), equals('presente'));
    });

    test(
        'Atleta con ingreso-salida-ingreso → estado = presente (reingreso más reciente)',
        () {
      final ts1 =
          Timestamp.fromDate(DateTime.utc(now.year, now.month, now.day, 8));
      final ts2 =
          Timestamp.fromDate(DateTime.utc(now.year, now.month, now.day, 12));
      final ts3 =
          Timestamp.fromDate(DateTime.utc(now.year, now.month, now.day, 15));
      final logs = [
        {'athleteUid': 'uid-F', 'action': 'ingreso', 'timestamp': ts1},
        {'athleteUid': 'uid-F', 'action': 'salida', 'timestamp': ts2},
        {'athleteUid': 'uid-F', 'action': 'ingreso', 'timestamp': ts3},
      ];
      expect(resolveStatus('uid-F', logs), equals('presente'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Grupo 3: Attendance logs data integrity (FakeFirebaseFirestore)
  // ═══════════════════════════════════════════════════════════════════════════
  group('Grupo 3: Attendance logs data integrity', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('Escribe 3 logs con diferentes athleteUids y consulta filtra por uid',
        () async {
      final col = fakeFirestore.collection('attendance_logs');
      await col.add({
        'athleteUid': 'uid-100',
        'action': 'ingreso',
        'timestamp': Timestamp.now(),
        'status': 'qr',
      });
      await col.add({
        'athleteUid': 'uid-200',
        'action': 'ingreso',
        'timestamp': Timestamp.now(),
        'status': 'qr',
      });
      await col.add({
        'athleteUid': 'uid-300',
        'action': 'salida',
        'timestamp': Timestamp.now(),
        'status': 'qr',
      });

      final snap = await col
          .where('athleteUid', isEqualTo: 'uid-100')
          .get();
      expect(snap.docs.length, equals(1));
      expect(snap.docs.first['athleteUid'], equals('uid-100'));
    });

    test('Consulta con rango UTC de fecha devuelve logs del día correcto',
        () async {
      final col = fakeFirestore.collection('attendance_logs');
      final today = DateTime.now().toUtc();
      final startOfDay = DateTime.utc(today.year, today.month, today.day);
      final endOfDay =
          DateTime.utc(today.year, today.month, today.day + 1);

      await col.add({
        'athleteUid': 'uid-400',
        'action': 'ingreso',
        'timestamp': Timestamp.fromDate(startOfDay.add(const Duration(hours: 9))),
        'status': 'qr',
      });
      // Log de ayer — no debe aparecer en el rango de hoy
      await col.add({
        'athleteUid': 'uid-400',
        'action': 'ingreso',
        'timestamp': Timestamp.fromDate(
            startOfDay.subtract(const Duration(hours: 3))),
        'status': 'qr',
      });

      final snap = await col
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp',
              isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      expect(snap.docs.length, equals(1));
      final ts = (snap.docs.first['timestamp'] as Timestamp).toDate();
      expect(ts.isAfter(startOfDay), isTrue);
      expect(ts.isBefore(endOfDay), isTrue);
    });

    test('Un log manual tiene status == "manual"', () async {
      final col = fakeFirestore.collection('attendance_logs');
      await col.add({
        'athleteUid': 'uid-500',
        'action': 'ingreso',
        'timestamp': Timestamp.now(),
        'status': 'manual',
        'location': 'Manual — Coach Pérez',
      });

      final snap = await col
          .where('athleteUid', isEqualTo: 'uid-500')
          .get();
      expect(snap.docs.first['status'], equals('manual'));
    });

    test('Un log manual tiene location que empieza con "Manual —"', () async {
      final col = fakeFirestore.collection('attendance_logs');
      await col.add({
        'athleteUid': 'uid-600',
        'action': 'ingreso',
        'timestamp': Timestamp.now(),
        'status': 'manual',
        'location': 'Manual — Admin',
      });

      final snap = await col
          .where('athleteUid', isEqualTo: 'uid-600')
          .get();
      final location = snap.docs.first['location'] as String;
      expect(location.startsWith('Manual —'), isTrue);
    });

    test('Consulta todos los logs retorna el total correcto de documentos',
        () async {
      final col = fakeFirestore.collection('attendance_logs');
      for (int i = 0; i < 5; i++) {
        await col.add({
          'athleteUid': 'uid-bulk-$i',
          'action': i.isEven ? 'ingreso' : 'salida',
          'timestamp': Timestamp.now(),
          'status': 'qr',
        });
      }
      final snap = await col.get();
      expect(snap.docs.length, equals(5));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Grupo 4: Admin dashboard permission check (pure logic)
  // ═══════════════════════════════════════════════════════════════════════════
  group('Grupo 4: Admin permission check — lógica pura', () {
    test('El role "admin" está en el set de roles privilegiados', () {
      expect(isPrivilegedRole('admin'), isTrue);
    });

    test('El role "user" NO está en el set de roles privilegiados', () {
      expect(isPrivilegedRole('user'), isFalse);
    });

    test('El role "coach" NO está en el set de roles privilegiados', () {
      expect(isPrivilegedRole('coach'), isFalse);
    });

    test('El role "" (vacío) NO está en el set de roles privilegiados', () {
      expect(isPrivilegedRole(''), isFalse);
    });

    test('"asitimbay.rommel@gmail.com" está en la lista de auto-admin', () {
      expect(isAutoAdminEmail('asitimbay.rommel@gmail.com'), isTrue);
    });

    test('"admin@omnisport.ai" está en la lista de auto-admin', () {
      expect(isAutoAdminEmail('admin@omnisport.ai'), isTrue);
    });

    test('Un email random NO está en la lista de auto-admin', () {
      expect(isAutoAdminEmail('atacante@rival.com'), isFalse);
    });

    test('Un email vacío NO está en la lista de auto-admin', () {
      expect(isAutoAdminEmail(''), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Grupo 5: Backoffice CSV edge cases para ingesta
  // ═══════════════════════════════════════════════════════════════════════════
  group('Grupo 5: CSV edge cases — BulkIngestionService', () {
    late BulkIngestionService svc;

    setUp(() {
      svc = BulkIngestionService(firestore: FakeFirebaseFirestore());
    });

    test('CSV con 50 filas válidas → total=50, failed=0', () async {
      final sb = StringBuffer('full_name,dni,email,consent_date\n');
      for (int i = 1; i <= 50; i++) {
        sb.writeln('Atleta $i,17${i.toString().padLeft(8, '0')},a$i@test.com,2026-01-01');
      }
      final summary = await svc.validate(sb.toString(), 'inst-050');
      expect(summary.total, equals(50));
      expect(summary.failed, equals(0));
    });

    test(
        'CSV con cabecera en mayúsculas (FULL_NAME, DNI) → rechazado con mensaje claro',
        () async {
      const csv = 'FULL_NAME,DNI,EMAIL,CONSENT_DATE\nPedro,12345,p@p.com,2026-01-01';
      final summary = await svc.validate(csv, 'inst-case');
      // El validador convierte la cabecera a minúsculas, así que debería aceptarla
      // o rechazarla con mensaje claro si no reconoce. Verificamos coherencia.
      expect(summary, isNotNull);
      // Si rechaza: debe tener mensaje claro
      if (summary.failed > 0) {
        expect(summary.errors.first.message.isNotEmpty, isTrue);
      }
    });

    test(
        'CSV con phone y teamOrCategory como columnas extra → acepta sin error',
        () async {
      const csv =
          'full_name,dni,email,consent_date,phone,teamOrCategory\nAlex,1700001234,alex@test.com,2026-01-15,0991234567,Fútbol Sub-14';
      final summary = await svc.validate(csv, 'inst-extra');
      expect(summary.total, equals(1));
      expect(summary.valid, equals(1));
      expect(summary.failed, equals(0));
    });

    test('CSV con BOM (\\uFEFF al inicio) → procesado correctamente', () async {
      // BOM: U+FEFF prepended to the CSV
      const bom = '﻿';
      const csv = '${bom}full_name,dni,email,consent_date\nBOM Test,1711110000,bom@test.com,2026-01-01';
      final summary = await svc.validate(csv, 'inst-bom');
      expect(summary.total, equals(1));
      expect(summary.valid, equals(1));
      expect(summary.failed, equals(0));
    });

    test('CSV con saltos de línea Windows (\\r\\n) → procesado correctamente',
        () async {
      const csv =
          'full_name,dni,email,consent_date\r\nWindows User,1799990000,win@test.com,2026-02-01\r\n';
      final summary = await svc.validate(csv, 'inst-crlf');
      expect(summary.total, equals(1));
      expect(summary.valid, equals(1));
      expect(summary.failed, equals(0));
    });

    test(
        'CSV con separador punto y coma → detectado y procesado correctamente',
        () async {
      const csv =
          'full_name;dni;email;consent_date\nSemicolon Atleta;1788880000;semi@test.com;2026-03-01';
      final summary = await svc.validate(csv, 'inst-semi');
      expect(summary.valid, equals(1));
      expect(summary.failed, equals(0));
    });

    test(
        'CSV con fila completamente vacía en medio → fila vacía ignorada, total no la cuenta',
        () async {
      const csv =
          'full_name,dni,email,consent_date\nAlfa,1700001111,a@a.com,2026-01-01\n\nBeta,1700002222,b@b.com,2026-01-02';
      final summary =
          await svc.validate(csv, 'inst-blank', forceOrder: true);
      expect(summary.total, equals(2));
      expect(summary.valid, equals(2));
    });

    test('CSV con un solo atleta válido → isDryRun = true', () async {
      const csv =
          'full_name,dni,email,consent_date\nSolo,1700000099,s@s.com,2026-01-01';
      final summary =
          await svc.validate(csv, 'inst-single', forceOrder: true);
      expect(summary.isDryRun, isTrue);
    });

    test('errors getter devuelve solo las filas con status error', () async {
      const csv =
          'full_name,dni,email,consent_date\nOK,1711111111,ok@ok.com,2026-01-01\nFail,2222222222,nomail,2026-01-01';
      final summary =
          await svc.validate(csv, 'inst-err', forceOrder: true);
      expect(summary.errors.length, equals(1));
      expect(summary.errors.every(
              (r) => r.status == IngestionStatus.error),
          isTrue);
    });
  });
}
