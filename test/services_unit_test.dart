/// Unit tests for service classes.
/// PreferencesService, OfflineSyncService static state, and BulkIngestionService extended.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:app/services/preferences_service.dart';
import 'package:app/services/offline_sync_service.dart';
import 'package:app/services/bulk_ingestion_service.dart';
import 'package:app/models/ingestion_result.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // PreferencesService
  // ─────────────────────────────────────────────────────────────────────────
  group('PreferencesService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService().init();
    });

    test('hasSeenOnboarding defaults to false when no value stored', () {
      expect(PreferencesService().hasSeenOnboarding, isFalse);
    });

    test('setHasSeenOnboarding(true) persists and reads back as true', () async {
      await PreferencesService().setHasSeenOnboarding(true);
      expect(PreferencesService().hasSeenOnboarding, isTrue);
    });

    test('setHasSeenOnboarding(false) resets the flag', () async {
      await PreferencesService().setHasSeenOnboarding(true);
      await PreferencesService().setHasSeenOnboarding(false);
      expect(PreferencesService().hasSeenOnboarding, isFalse);
    });

    test('preferredLanguage defaults to null when nothing is stored', () {
      expect(PreferencesService().preferredLanguage, isNull);
    });

    test('setPreferredLanguage("es") persists Spanish code', () async {
      await PreferencesService().setPreferredLanguage('es');
      expect(PreferencesService().preferredLanguage, equals('es'));
    });

    test('setPreferredLanguage("en") persists English code', () async {
      await PreferencesService().setPreferredLanguage('en');
      expect(PreferencesService().preferredLanguage, equals('en'));
    });

    test('overwriting language preference works correctly', () async {
      await PreferencesService().setPreferredLanguage('es');
      await PreferencesService().setPreferredLanguage('en');
      expect(PreferencesService().preferredLanguage, equals('en'));
    });

    test('is a singleton — multiple instances share the same state', () async {
      await PreferencesService().setPreferredLanguage('es');
      final another = PreferencesService();
      expect(another.preferredLanguage, equals('es'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // OfflineSyncService — static state only (no Hive/Firestore needed)
  // ─────────────────────────────────────────────────────────────────────────
  group('OfflineSyncService static state', () {
    setUp(() {
      OfflineSyncService.forceOfflineMode = false;
      OfflineSyncService.lastSyncResponse = 'No sync attempted';
    });

    test('forceOfflineMode starts as false', () {
      expect(OfflineSyncService.forceOfflineMode, isFalse);
    });

    test('forceOfflineMode can be toggled to true', () {
      OfflineSyncService.forceOfflineMode = true;
      expect(OfflineSyncService.forceOfflineMode, isTrue);
    });

    test('forceOfflineMode toggle round-trip', () {
      OfflineSyncService.forceOfflineMode = true;
      OfflineSyncService.forceOfflineMode = !OfflineSyncService.forceOfflineMode;
      expect(OfflineSyncService.forceOfflineMode, isFalse);
    });

    test('lastSyncResponse has a non-empty default', () {
      expect(OfflineSyncService.lastSyncResponse.isNotEmpty, isTrue);
    });

    test('lastSyncResponse can be set to any string', () {
      OfflineSyncService.lastSyncResponse = 'Success: Synced 5 records';
      expect(OfflineSyncService.lastSyncResponse, equals('Success: Synced 5 records'));
    });

    test('syncLogs skips when forceOfflineMode is true (no exception thrown)', () async {
      OfflineSyncService.forceOfflineMode = true;
      // Should return without crash in test environment
      await expectLater(
        OfflineSyncService.syncLogs(firestore: FakeFirebaseFirestore()),
        completes,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BulkIngestionService — extended validation cases
  // ─────────────────────────────────────────────────────────────────────────
  group('BulkIngestionService extended', () {
    late BulkIngestionService svc;

    setUp(() {
      svc = BulkIngestionService(firestore: FakeFirebaseFirestore());
    });

    // ── Header validation ──────────────────────────────────────────────────

    test('rejects CSV missing full_name column', () async {
      const csv = 'dni,email,consent_date\n1234567890,x@x.com,2026-01-01';
      final s = await svc.validate(csv, 'inst');
      expect(s.failed, greaterThan(0));
      expect(s.errors.first.message, contains('CABECERA INVÁLIDA'));
    });

    test('rejects CSV missing dni column', () async {
      const csv = 'full_name,email,consent_date\nJuan,x@x.com,2026-01-01';
      final s = await svc.validate(csv, 'inst');
      expect(s.errors.first.message, contains('CABECERA INVÁLIDA'));
    });

    test('rejects CSV missing consent_date column', () async {
      const csv = 'full_name,dni,email\nJuan,123,x@x.com';
      final s = await svc.validate(csv, 'inst');
      expect(s.errors.first.message, contains('CABECERA INVÁLIDA'));
    });

    test('rejects empty CSV string', () async {
      final s = await svc.validate('', 'inst');
      expect(s.failed, greaterThan(0));
    });

    test('rejects CSV with only whitespace', () async {
      final s = await svc.validate('   \n  ', 'inst');
      expect(s.failed, greaterThan(0));
    });

    // ── Row validation ────────────────────────────────────────────────────

    test('rejects row with empty DNI', () async {
      const csv = 'full_name,dni,email,consent_date\nCarlos,,carlos@test.com,2026-05-01';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.failed, equals(1));
      expect(s.errors.first.message, contains('[ERROR DATO] DNI vacío'));
    });

    test('rejects row with missing consent date', () async {
      const csv = 'full_name,dni,email,consent_date\nCarlos,12345,carlos@test.com,';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.failed, equals(1));
      expect(s.errors.first.message, contains('[ERROR CRÍTICO LOPDP]'));
    });

    test('rejects consent date in DD/MM/YYYY format', () async {
      const csv = 'full_name,dni,email,consent_date\nAna,12345,ana@test.com,18/05/2026';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.errors.first.message, contains('[ERROR FORMATO] Fecha'));
    });

    test('rejects consent date in MM-DD-YYYY format', () async {
      const csv = 'full_name,dni,email,consent_date\nAna,12345,ana@test.com,05-18-2026';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.errors.first.message, contains('[ERROR FORMATO] Fecha'));
    });

    test('accepts consent date in YYYY-MM-DD format', () async {
      const csv = 'full_name,dni,email,consent_date\nAna,12345,ana@test.com,2026-05-18';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.valid, equals(1));
      expect(s.failed, equals(0));
    });

    test('rejects email missing @ symbol', () async {
      const csv = 'full_name,dni,email,consent_date\nX,123,notanemail,2026-01-01';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.errors.first.message, contains('[ERROR FORMATO] Email inválido'));
    });

    test('rejects email with no domain after @', () async {
      const csv = 'full_name,dni,email,consent_date\nX,123,user@,2026-01-01';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.errors.first.message, contains('Email inválido'));
    });

    test('accepts row with no email (optional field)', () async {
      const csv = 'full_name,dni,email,consent_date\nX,12345,,2026-01-01';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.valid, equals(1));
    });

    // ── Mixed batch ───────────────────────────────────────────────────────

    test('correctly counts valid and failed across a mixed batch of 4 rows', () async {
      const csv = '''full_name,dni,email,consent_date
Valid One,111,v1@test.com,2026-01-01
Bad Email,222,bademail,2026-01-01
No Consent,333,v3@test.com,
Valid Two,444,v4@test.com,2026-03-15''';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.total,  equals(4));
      expect(s.valid,  equals(2));
      expect(s.failed, equals(2));
    });

    test('skips completely blank rows in total count', () async {
      const csv = '''full_name,dni,email,consent_date
Valid,111,v@v.com,2026-01-01

Valid2,222,v2@v.com,2026-02-01''';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.total, equals(2));
    });

    // ── Separator detection ───────────────────────────────────────────────

    test('detects semicolon-delimited CSV', () async {
      const csv = 'full_name;dni;email;consent_date\nPedro;9876;pedro@test.com;2026-04-10';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.valid, equals(1));
    });

    // ── Output content ────────────────────────────────────────────────────

    test('valid row message contains masked DNI', () async {
      const csv = 'full_name,dni,email,consent_date\nEva,1723456789,eva@test.com,2026-05-18';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.rows.first.message, contains('•'));
      expect(s.rows.first.message, isNot(contains('1723456789')));
    });

    test('isDryRun is always true from client-side validator', () async {
      const csv = 'full_name,dni,email,consent_date\nX,1,,2026-01-01';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      expect(s.isDryRun, isTrue);
    });

    // ── Report string ─────────────────────────────────────────────────────

    test('toReportString contains execution timestamp', () async {
      const csv = 'full_name,dni,email,consent_date\nX,1,x@x.com,2026-01-01';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      final report = s.toReportString('inst');
      expect(report, contains('2026'));
    });

    test('toReportString has fixed audit header and footer markers', () async {
      const csv = 'full_name,dni,email,consent_date\nX,1,x@x.com,2026-01-01';
      final s = await svc.validate(csv, 'inst', forceOrder: true);
      final report = s.toReportString('inst');
      expect(report, contains('AUDITORÍA FORENSE'));
      expect(report, contains('===='));
    });
  });
}
