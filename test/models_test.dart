/// Unit tests for all data models.
/// Pure Dart — no Firebase, no plugins needed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/athlete.dart';
import 'package:app/models/session_model.dart';
import 'package:app/models/ingestion_result.dart';
import 'package:app/models/smart_id_credential.dart';

// Fake Timestamp for Athlete.fromMap tests (avoids cloud_firestore dependency)
class _FakeTimestamp {
  final DateTime _dt;
  _FakeTimestamp(this._dt);
  DateTime toDate() => _dt;
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Athlete
  // ─────────────────────────────────────────────────────────────────────────
  group('Athlete.fromMap', () {
    test('maps all standard fields correctly', () {
      final data = {
        'full_name': 'Carlos Vera',
        'photoUrl': 'https://img.example.com/photo.jpg',
        'teamOrCategory': 'Sub 16',
        'paymentStatus': 'Al Día',
        'status': 'Acceso Autorizado',
        'representativeUid': 'rep_001',
        'parent_uid': 'parent_001',
        'attendance_token': 'tok_abc',
        'emergency_contact': '+593987654321',
      };
      final athlete = Athlete.fromMap('uid_cv', data);

      expect(athlete.uid,                equals('uid_cv'));
      expect(athlete.fullName,           equals('Carlos Vera'));
      expect(athlete.photoUrl,           equals('https://img.example.com/photo.jpg'));
      expect(athlete.teamOrCategory,     equals('Sub 16'));
      expect(athlete.paymentStatus,      equals('Al Día'));
      expect(athlete.status,             equals('Acceso Autorizado'));
      expect(athlete.representativeUid,  equals('rep_001'));
      expect(athlete.parentUid,          equals('parent_001'));
      expect(athlete.attendanceToken,    equals('tok_abc'));
      expect(athlete.emergencyContact,   equals('+593987654321'));
      expect(athlete.lastMedicalReview,  isNull);
    });

    test('uses safe defaults for missing optional fields', () {
      final athlete = Athlete.fromMap('uid_empty', {});

      expect(athlete.fullName,          equals('Atleta Nuevo'));
      expect(athlete.photoUrl,          equals(''));
      expect(athlete.teamOrCategory,    equals('Sin Categoría'));
      expect(athlete.paymentStatus,     equals('Al Día'));
      expect(athlete.status,            equals('Acceso Autorizado'));
      expect(athlete.representativeUid, equals(''));
      expect(athlete.parentUid,         isNull);
      expect(athlete.attendanceToken,   isNull);
      expect(athlete.emergencyContact,  isNull);
    });

    test('does not crash with null values in map', () {
      final data = {
        'full_name': null,
        'photoUrl': null,
        'teamOrCategory': null,
        'paymentStatus': null,
        'status': null,
        'representativeUid': null,
      };
      expect(() => Athlete.fromMap('uid_nulls', data), returnsNormally);
    });

    test('uid field is preserved from constructor argument, not from map', () {
      final athlete = Athlete.fromMap('custom_uid_123', {'full_name': 'Test'});
      expect(athlete.uid, equals('custom_uid_123'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SessionModel
  // ─────────────────────────────────────────────────────────────────────────
  group('SessionModel', () {
    SessionModel _makeSession() => SessionModel(
      id:                     'sess_001',
      athleteId:              'uid_ana',
      sport:                  'Fútbol',
      ejerciciosCompletados:  12,
      atletaNombre:           'Ana López',
      tipo:                   'Fuerza',
      fecha:                  DateTime(2026, 5, 18),
    );

    test('toMap exports the 4 fields used for Firestore sync', () {
      final map = _makeSession().toMap();

      expect(map['sport'],                    equals('Fútbol'));
      expect(map['ejercicios_completados'],   equals(12));
      expect(map['atleta'],                   equals('Ana López'));
      expect(map['tipo'],                     equals('Fuerza'));
    });

    test('toMap does NOT include id, athleteId, or fecha (backend handles timestamp)', () {
      final map = _makeSession().toMap();
      expect(map.containsKey('id'),         isFalse);
      expect(map.containsKey('athleteId'),  isFalse);
      expect(map.containsKey('fecha'),      isFalse);
    });

    test('ejerciciosCompletados of 0 is valid (rest day)', () {
      final s = SessionModel(
        id: 'rest', athleteId: 'x', sport: 'Descanso',
        ejerciciosCompletados: 0, atletaNombre: 'X', tipo: 'Recuperación',
        fecha: DateTime.now(),
      );
      expect(s.toMap()['ejercicios_completados'], equals(0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // IngestionResult / IngestionSummary
  // ─────────────────────────────────────────────────────────────────────────
  group('IngestionSummary', () {
    IngestionSummary _makeSummary({
      int total = 3,
      int valid = 2,
      int failed = 1,
      bool isDryRun = true,
    }) {
      return IngestionSummary(
        total:       total,
        valid:       valid,
        failed:      failed,
        isDryRun:    isDryRun,
        rows: [
          const IngestionRowResult(rowNumber: 2, name: 'Juan', status: IngestionStatus.valid,   message: 'OK'),
          const IngestionRowResult(rowNumber: 3, name: 'Pedro', status: IngestionStatus.valid,  message: 'OK'),
          const IngestionRowResult(rowNumber: 4, name: 'Fallo', status: IngestionStatus.error,  message: '[ERROR] DNI vacío'),
        ],
        executedAt: DateTime(2026, 5, 18, 10, 0, 0),
      );
    }

    test('errors getter returns only error rows', () {
      final summary = _makeSummary();
      expect(summary.errors.length,         equals(1));
      expect(summary.errors.first.name,     equals('Fallo'));
    });

    test('errors getter is empty when all rows pass', () {
      final summary = IngestionSummary(
        total: 1, valid: 1, failed: 0, isDryRun: true,
        rows: [const IngestionRowResult(rowNumber: 2, name: 'Ana', status: IngestionStatus.valid, message: 'OK')],
        executedAt: DateTime.now(),
      );
      expect(summary.errors, isEmpty);
    });

    test('toReportString includes DRY RUN label when isDryRun is true', () {
      final report = _makeSummary(isDryRun: true).toReportString('inst_test');
      expect(report, contains('SIMULACIÓN DRY RUN'));
      expect(report, contains('Base de datos NO alterada'));
    });

    test('toReportString includes PRODUCCIÓN label when isDryRun is false', () {
      final report = _makeSummary(isDryRun: false).toReportString('inst_test');
      expect(report, contains('EJECUCIÓN EN PRODUCCIÓN'));
      expect(report, contains('Cloud Function'));
    });

    test('toReportString includes institution ID', () {
      final report = _makeSummary().toReportString('academia_quito');
      expect(report, contains('academia_quito'));
    });

    test('toReportString includes error detail for failed rows', () {
      final report = _makeSummary().toReportString('inst');
      expect(report, contains('Fallo'));
      expect(report, contains('[ERROR] DNI vacío'));
    });

    test('toReportString shows "Ninguna incongruencia" when no errors', () {
      final summary = IngestionSummary(
        total: 1, valid: 1, failed: 0, isDryRun: true,
        rows: [const IngestionRowResult(rowNumber: 2, name: 'X', status: IngestionStatus.valid, message: 'OK')],
        executedAt: DateTime.now(),
      );
      expect(summary.toReportString('inst'), contains('Ninguna incongruencia'));
    });

    test('total, valid, failed counts are reflected in report', () {
      final report = _makeSummary(total: 10, valid: 8, failed: 2).toReportString('inst');
      expect(report, contains('10'));
      expect(report, contains('8'));
      expect(report, contains('2'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // IngestionRowResult
  // ─────────────────────────────────────────────────────────────────────────
  group('IngestionRowResult', () {
    test('status enum has exactly 2 values', () {
      expect(IngestionStatus.values.length, equals(2));
    });

    test('valid status is distinct from error status', () {
      expect(IngestionStatus.valid, isNot(equals(IngestionStatus.error)));
    });

    test('can construct with all fields', () {
      const row = IngestionRowResult(
        rowNumber: 5,
        name: 'María García',
        status: IngestionStatus.error,
        message: '[ERROR CRÍTICO LOPDP] Consentimiento no proporcionado.',
      );
      expect(row.rowNumber, equals(5));
      expect(row.name,      equals('María García'));
      expect(row.status,    equals(IngestionStatus.error));
      expect(row.message,   contains('LOPDP'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SmartIdCredential (extended — complements ios_crash_regression_test)
  // ─────────────────────────────────────────────────────────────────────────
  group('SmartIdCredential extended', () {
    test('isExpired uses millisecondsSinceEpoch comparison, not Date equality', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final justExpired  = SmartIdCredential.fromMap({'expMs': now - 1});
      final aboutToExpire = SmartIdCredential.fromMap({'expMs': now + 60000});
      expect(justExpired.isExpired,   isTrue);
      expect(aboutToExpire.isExpired, isFalse);
    });

    test('expiryDate converts expMs to DateTime correctly', () {
      final ms = DateTime(2026, 12, 31, 23, 59).millisecondsSinceEpoch;
      final cred = SmartIdCredential.fromMap({'expMs': ms});
      expect(cred.expiryDate.year,  equals(2026));
      expect(cred.expiryDate.month, equals(12));
      expect(cred.expiryDate.day,   equals(31));
    });

    test('toMap produces a map with 12 keys', () {
      final cred = SmartIdCredential.fromMap({
        'athleteUid': 'u1', 'token': 't', 'smartIdNum': 'SMT-1',
        'isEligible': true, 'expMs': 0, 'cachedAtMs': 0,
        'fullName': 'X', 'category': 'Y', 'photoUrl': '',
        'medicalOk': true, 'paymentOk': false, 'institutionId': 'i1',
      });
      expect(cred.toMap().keys.length, equals(12));
    });
  });
}
