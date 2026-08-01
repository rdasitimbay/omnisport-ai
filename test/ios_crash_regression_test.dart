/// Regression tests for the 3 iOS crash scenarios identified in Sprint 4.
///
/// Covers:
///   1. SmartIdCredential — serialization, expiry, JWT decode (Sport Passport crash)
///   2. InjuryType enum — completeness and key uniqueness (SOS crash)
///   3. QR token shape detection — pure logic mirror of _isSmartIdToken (QR Scanner crash)
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/smart_id_credential.dart';
import 'package:app/screens/sos_alert_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helper: mirrors production _isSmartIdToken logic from qr_scanner_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
bool _isSmartIdToken(String raw) {
  final parts = raw.split('.');
  if (parts.length != 3) return false;
  try {
    final padded = base64Url.normalize(parts[0]);
    final header = json.decode(utf8.decode(base64Url.decode(padded))) as Map;
    return header['typ'] == 'SMART_ID';
  } catch (_) {
    return false;
  }
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1. SmartIdCredential — serialization round-trip & expiry
  // ─────────────────────────────────────────────────────────────────────────
  group('SmartIdCredential', () {
    SmartIdCredential _makeCred({required bool expired}) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return SmartIdCredential(
        athleteUid:    'uid_test',
        token:         'h.p.s',
        smartIdNum:    'SMT-2024-001',
        isEligible:    true,
        expMs:         expired ? now - 1000 : now + 86400000,
        cachedAtMs:    now,
        fullName:      'Juan Perez',
        category:      'Sub 18',
        photoUrl:      '',
        medicalOk:     true,
        paymentOk:     true,
        institutionId: 'inst1',
      );
    }

    test('isExpired → true when expMs is in the past', () {
      expect(_makeCred(expired: true).isExpired, isTrue);
    });

    test('isExpired → false when expMs is in the future', () {
      expect(_makeCred(expired: false).isExpired, isFalse);
    });

    test('toMap / fromMap round-trip preserves all fields', () {
      final cred = _makeCred(expired: false);
      final restored = SmartIdCredential.fromMap(cred.toMap());

      expect(restored.athleteUid,    equals(cred.athleteUid));
      expect(restored.smartIdNum,    equals(cred.smartIdNum));
      expect(restored.isEligible,    equals(cred.isEligible));
      expect(restored.medicalOk,     equals(cred.medicalOk));
      expect(restored.paymentOk,     equals(cred.paymentOk));
      expect(restored.fullName,      equals(cred.fullName));
      expect(restored.category,      equals(cred.category));
      expect(restored.institutionId, equals(cred.institutionId));
      expect(restored.expMs,         equals(cred.expMs));
    });

    test('fromMap with empty map returns safe defaults (no crash)', () {
      final cred = SmartIdCredential.fromMap({});
      expect(cred.athleteUid,  equals(''));
      expect(cred.isEligible,  isFalse);
      expect(cred.medicalOk,   isFalse);
      expect(cred.paymentOk,   isFalse);
      expect(cred.expMs,       equals(0));
    });

    test('fromTokenResponse decodes JWT payload fullName and category', () {
      // payload = {"fullName":"Ana López","category":"Sub 14","photoUrl":"","institutionId":"inst2"}
      const jwt =
          'eyJ0eXAiOiJTTUFSVF9JRCJ9'
          '.eyJmdWxsTmFtZSI6IkFuYSBMw7NwZXoiLCJjYXRlZ29yeSI6IlN1YiAxNCIsInBob3RvVXJsIjoiIiwiaW5zdGl0dXRpb25JZCI6Imluc3QyIn0'
          '.fakesig';
      final now = DateTime.now().millisecondsSinceEpoch;
      final cred = SmartIdCredential.fromTokenResponse(
        athleteUid: 'uid_ana',
        token:      jwt,
        smartIdNum: 'SMT-2024-002',
        isEligible: true,
        medicalOk:  true,
        paymentOk:  false,
        expMs:      now + 86400000,
      );
      expect(cred.fullName, equals('Ana López'));
      expect(cred.category, equals('Sub 14'));
    });

    test('fromTokenResponse handles malformed JWT without crashing', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final cred = SmartIdCredential.fromTokenResponse(
        athleteUid: 'uid_bad',
        token:      'not.a.valid.jwt.payload',
        smartIdNum: 'SMT-BAD',
        isEligible: false,
        medicalOk:  false,
        paymentOk:  false,
        expMs:      now + 3600000,
      );
      expect(cred.fullName, equals(''));
      expect(cred.category, equals(''));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. InjuryType enum — SOS catalog completeness
  // ─────────────────────────────────────────────────────────────────────────
  group('InjuryType', () {
    test('covers exactly 8 distinct injury types', () {
      expect(InjuryType.values.length, equals(8));
    });

    test('all values have non-empty key and label', () {
      for (final injury in InjuryType.values) {
        expect(injury.key.isNotEmpty,   isTrue,  reason: '${injury.name}: key vacío');
        expect(injury.label.isNotEmpty, isTrue,  reason: '${injury.name}: label vacío');
      }
    });

    test('keys are unique across all injury types', () {
      final keys = InjuryType.values.map((e) => e.key).toList();
      expect(keys.toSet().length, equals(keys.length));
    });

    test('high-severity types map to correct keys', () {
      expect(InjuryType.golpeCabeza.key,            equals('golpe_cabeza'));
      expect(InjuryType.dificultadRespiratoria.key, equals('dificultad_respiratoria'));
      expect(InjuryType.fracturaSospecha.key,       equals('fractura_sospecha'));
    });

    test('contusion and esguince are low/medium severity (green/amber colors)', () {
      // Color value 0xFF4CAF50 = green, 0xFFFFAB40 = amber
      expect(InjuryType.contusion.color.value,  equals(const Color(0xFF4CAF50).value));
      expect(InjuryType.esguince.color.value,   equals(const Color(0xFFFFAB40).value));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. QR Token shape — mirrors _isSmartIdToken from qr_scanner_screen.dart
  // ─────────────────────────────────────────────────────────────────────────
  group('_isSmartIdToken', () {
    test('plain UID without dots is rejected', () {
      expect(_isSmartIdToken('QKMTwTj8aDbsA519jC4xGsVyc1I'), isFalse);
    });

    test('string with only 2 dot-parts is rejected', () {
      expect(_isSmartIdToken('abc.def'), isFalse);
    });

    test('3-part string with invalid base64 header is rejected', () {
      expect(_isSmartIdToken('!!!.payload.sig'), isFalse);
    });

    test('3-part JWT without typ=SMART_ID is rejected', () {
      // header = {"typ":"JWT","alg":"HS256"}
      final header = base64Url.encode(utf8.encode(json.encode({'typ': 'JWT', 'alg': 'HS256'})));
      expect(_isSmartIdToken('$header.payload.sig'), isFalse);
    });

    test('3-part JWT with typ=SMART_ID is accepted', () {
      final header = base64Url.encode(utf8.encode(json.encode({'typ': 'SMART_ID', 'alg': 'HS256'})));
      expect(_isSmartIdToken('$header.payload.sig'), isTrue);
    });

    test('empty string is rejected without crash', () {
      expect(_isSmartIdToken(''), isFalse);
    });
  });
}

// ignore: avoid_classes_with_only_static_members
class Color {
  final int value;
  const Color(this.value);
}
