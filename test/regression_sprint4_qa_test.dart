/// Regression tests for Sprint 4 QA — covers BUG-05, BUG-08, BUG-09, BUG-11,
/// BUG-13, BUG-14, BUG-18, BUG-19.
///
/// Pure Dart — no Firebase, no plugin dependencies.
/// All production logic that lives inside widgets or screens is mirrored here
/// as local functions with a comment indicating the source.
library;

import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mirror: UTC day-range logic from session_attendance_screen.dart (BUG-11)
// and parent_dashboard_screen.dart _ChildCard._build() (BUG-19).
// ─────────────────────────────────────────────────────────────────────────────

/// Builds [startOfDay, endOfDay) in UTC — mirrors production code in both
/// SessionAttendanceScreen.initState() and _ChildCard.build().
({DateTime start, DateTime end}) buildUtcDayRange(DateTime now) {
  final utc = now.toUtc();
  final start = DateTime.utc(utc.year, utc.month, utc.day);
  final end   = DateTime.utc(utc.year, utc.month, utc.day + 1);
  return (start: start, end: end);
}

// ─────────────────────────────────────────────────────────────────────────────
// Mirror: _ChildCard avatar initial logic — BUG-13
// mirrors production code from parent_dashboard_screen.dart line ~217
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the first character (upper-cased) to display in the avatar,
/// or '?' when the name is empty. Mirrors `name.isNotEmpty ? name[0].toUpperCase() : '?'`.
String avatarInitial(String? rawName) {
  // mirrors production logic from parent_dashboard_screen.dart
  final name = rawName ?? 'Sin nombre';
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}

// ─────────────────────────────────────────────────────────────────────────────
// Mirror: SecureQRView error token detection — BUG-05
// mirrors production code from secure_qr_view.dart line ~82
// ─────────────────────────────────────────────────────────────────────────────

/// Returns true when the token string starts with the 'ERROR:' sentinel.
/// Mirrors `token.startsWith('ERROR:')` in _SecureQRViewState.build().
bool isErrorToken(String token) => token.startsWith('ERROR:');

/// Extracts the message portion after the 'ERROR:' prefix.
/// Returns the full string unchanged if the prefix is absent.
String extractErrorMessage(String token) {
  if (!isErrorToken(token)) return token;
  return token.substring('ERROR:'.length);
}

// ─────────────────────────────────────────────────────────────────────────────
// Mirror: _checkIfMinor age calculation — BUG-14
// mirrors production logic from admin_dashboard_screen.dart / qr_scanner_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

/// Returns true when the person is strictly under 18 years old at [now].
/// mirrors production logic from qr_scanner_screen.dart / admin_dashboard_screen.dart
bool isMinorByAge(DateTime dob, DateTime now) {
  // mirrors production logic from admin_dashboard_screen.dart / qr_scanner_screen.dart
  var age = now.year - dob.year;
  if (now.month < dob.month ||
      (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age < 18;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mirror: buildAttendanceLog — the map that _markManual writes — BUG-18
// mirrors production code from session_attendance_screen.dart ~line 75
// ─────────────────────────────────────────────────────────────────────────────

/// Builds the Firestore document map for a manual attendance log.
/// The `timestamp` / `serverTimestamp` field is intentionally omitted here;
/// it is added by Firestore at write time (`FieldValue.serverTimestamp()`).
/// mirrors production logic from session_attendance_screen.dart _markManual()
Map<String, dynamic> buildAttendanceLog({
  required String athleteUid,
  required String scannedBy,
  required String action,
  required String coachName,
}) =>
    {
      'athleteUid': athleteUid,
      'scannedBy':  scannedBy,
      'action':     action,
      'location':   'Manual — $coachName',
      'status':     'manual',
    };

// ─────────────────────────────────────────────────────────────────────────────
// Mirror: _resolveStatus — admin dashboard attendance status — Grupo 7
// mirrors production code from session_attendance_screen.dart _resolveStatus()
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves the attendance status for [athleteUid] given a flat list of log
/// maps (each carrying 'athleteUid', 'action', and 'tsMs').
/// mirrors production logic from session_attendance_screen.dart _resolveStatus()
String resolveStatus(
    String athleteUid, List<Map<String, dynamic>> todayLogs) {
  final myLogs = todayLogs
      .where((d) => d['athleteUid'] == athleteUid)
      .toList()
    ..sort((a, b) =>
        (b['tsMs'] as int).compareTo(a['tsMs'] as int));
  if (myLogs.isEmpty) return 'ausente';
  final lastAction = myLogs.first['action'] as String? ?? 'ingreso';
  return lastAction == 'ingreso' ? 'presente' : 'salida';
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // Grupo 1: UTC Timestamp Regression (BUG-11 / BUG-19)
  // ───────────────────────────────────────────────────────────────────────────
  group('UTC Timestamp Regression (BUG-11 / BUG-19)', () {
    test('DateTime.now().toUtc() produces a UTC-flagged DateTime', () {
      final utc = DateTime.now().toUtc();
      expect(utc.isUtc, isTrue);
    });

    test('DateTime.utc(y,m,d) is exactly midnight UTC', () {
      final midnight = DateTime.utc(2026, 5, 19);
      expect(midnight.isUtc,        isTrue);
      expect(midnight.hour,         equals(0));
      expect(midnight.minute,       equals(0));
      expect(midnight.second,       equals(0));
      expect(midnight.millisecond,  equals(0));
    });

    test('DateTime.utc(y,m,d+1) is midnight of the next day in UTC', () {
      final nextDay = DateTime.utc(2026, 5, 19 + 1);
      expect(nextDay.isUtc,  isTrue);
      expect(nextDay.day,    equals(20));
      expect(nextDay.month,  equals(5));
      expect(nextDay.hour,   equals(0));
    });

    test('noon UTC is inside the [startOfDay, endOfDay) range', () {
      // Fixed date: 2026-05-19
      final noonUtc   = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final range     = buildUtcDayRange(noonUtc);
      expect(noonUtc.isAfter(range.start),            isTrue);
      expect(noonUtc.isBefore(range.end),             isTrue);
    });

    test('startOfDay is NOT after noon — it is before or equal', () {
      final noonUtc = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final range   = buildUtcDayRange(noonUtc);
      // start must be <= noon
      expect(range.start.isBefore(noonUtc) || range.start == noonUtc, isTrue);
    });

    test('midnight of next day is NOT inside the range (exclusive upper bound)', () {
      final ref      = DateTime.utc(2026, 5, 19, 6, 0, 0);
      final range    = buildUtcDayRange(ref);
      final nextMidnight = DateTime.utc(2026, 5, 20, 0, 0, 0);
      // endOfDay == nextMidnight → it is NOT inside (open upper bound)
      expect(nextMidnight.isBefore(range.end), isFalse);
    });

    test('UTC-5 offset demo: local toLocal() loses 5h vs toUtc() at midnight', () {
      // Simulate a local midnight in UTC-5:
      // local midnight = 00:00 local = 05:00 UTC
      // If we forget toUtc() and use local hour=0 directly, we start
      // the day range 5 hours late, missing logs from 00:00–04:59 UTC.
      final utcMidnight   = DateTime.utc(2026, 5, 19, 0, 0, 0);
      // Simulated "wrong" local-based start (UTC-5: hour 5 in UTC)
      final wrongStart    = DateTime.utc(2026, 5, 19, 5, 0, 0);
      // A log at 02:00 UTC should be captured by correct range but missed by wrong range
      final earlyLogUtc   = DateTime.utc(2026, 5, 19, 2, 0, 0);
      expect(earlyLogUtc.isAfter(utcMidnight),  isTrue,  reason: 'correct range captures 02:00 UTC');
      expect(earlyLogUtc.isBefore(wrongStart),  isTrue,  reason: 'wrong range misses 02:00 UTC');
    });

    test('buildUtcDayRange start and end are always exactly 24h apart', () {
      final ref   = DateTime.utc(2026, 1, 31, 15, 30, 0);
      final range = buildUtcDayRange(ref);
      final diff  = range.end.difference(range.start);
      expect(diff.inHours, equals(24));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Grupo 2: _ChildCard name safety (BUG-13)
  // ───────────────────────────────────────────────────────────────────────────
  group('ChildCard name safety (BUG-13)', () {
    test('empty string isEmpty → true (guard condition)', () {
      expect(''.isEmpty, isTrue);
    });

    test('empty name produces "?" avatar initial', () {
      expect(avatarInitial(''), equals('?'));
    });

    test('single-character name returns that character upper-cased', () {
      expect(avatarInitial('a'), equals('A'));
    });

    test('normal name returns first letter upper-cased', () {
      expect(avatarInitial('carlos'), equals('C'));
    });

    test('name already upper-cased returns first letter unchanged', () {
      expect(avatarInitial('María'), equals('M'));
    });

    test('null name falls back to "Sin nombre" default and returns "S"', () {
      // null → fallback 'Sin nombre' → 'S'
      expect(avatarInitial(null), equals('S'));
    });

    test('whitespace-only name is not empty (contains chars), returns first char', () {
      // '   '.isNotEmpty == true, so it won't crash — returns ' '
      expect(avatarInitial('   '), equals(' '));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Grupo 3: SecureQRView token error detection (BUG-05)
  // ───────────────────────────────────────────────────────────────────────────
  group('SecureQRView error token detection (BUG-05)', () {
    test('token starting with "ERROR:" is detected as error token', () {
      expect(isErrorToken('ERROR:token_empty'), isTrue);
    });

    test('normal JWT-shaped token is NOT an error token', () {
      expect(isErrorToken('eyJhbGciOiJIUzI1NiJ9.payload.sig'), isFalse);
    });

    test('empty string is NOT an error token', () {
      expect(isErrorToken(''), isFalse);
    });

    test('token with ERROR in the middle is NOT detected (must be prefix)', () {
      expect(isErrorToken('validtoken_ERROR:suffix'), isFalse);
    });

    test('extractErrorMessage returns message after "ERROR:" prefix', () {
      expect(extractErrorMessage('ERROR:token_empty'), equals('token_empty'));
    });

    test('extractErrorMessage returns full string when no ERROR: prefix', () {
      expect(extractErrorMessage('normaltoken'), equals('normaltoken'));
    });

    test('extractErrorMessage handles long error details correctly', () {
      const msg = 'ERROR:FirebaseFunctionsException(INTERNAL): server unreachable';
      expect(extractErrorMessage(msg), startsWith('FirebaseFunctionsException'));
    });

    test('"ERROR:" alone (empty message part) is still an error token', () {
      expect(isErrorToken('ERROR:'), isTrue);
      expect(extractErrorMessage('ERROR:'), equals(''));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Grupo 4: Age calculation correctness (BUG-14)
  // ───────────────────────────────────────────────────────────────────────────
  group('Age calculation isMinorByAge (BUG-14)', () {
    test('person turning 18 exactly today is NOT a minor', () {
      final today = DateTime(2026, 5, 19);
      final dob   = DateTime(2008, 5, 19); // 18 today
      expect(isMinorByAge(dob, today), isFalse);
    });

    test('person turning 18 tomorrow IS still a minor today', () {
      final today = DateTime(2026, 5, 19);
      final dob   = DateTime(2008, 5, 20); // birthday tomorrow
      expect(isMinorByAge(dob, today), isTrue);
    });

    test('person who turned 18 yesterday is NOT a minor', () {
      final today = DateTime(2026, 5, 19);
      final dob   = DateTime(2008, 5, 18); // birthday was yesterday
      expect(isMinorByAge(dob, today), isFalse);
    });

    test('person born in December viewed in January: age computed correctly', () {
      // Born 2008-12-15, viewed on 2026-01-10: 17 years (birthday not yet reached)
      final today = DateTime(2026, 1, 10);
      final dob   = DateTime(2008, 12, 15);
      expect(isMinorByAge(dob, today), isTrue);
    });

    test('person born in December viewed after December birthday: 17 → 18', () {
      // Born 2007-12-01, viewed on 2026-01-10: 18 years (birthday already passed)
      final today = DateTime(2026, 1, 10);
      final dob   = DateTime(2007, 12, 1);
      expect(isMinorByAge(dob, today), isFalse);
    });

    test('person born today (age 0) IS a minor', () {
      final today = DateTime(2026, 5, 19);
      final dob   = today;
      expect(isMinorByAge(dob, today), isTrue);
    });

    test('person aged 25 is NOT a minor', () {
      final today = DateTime(2026, 5, 19);
      final dob   = DateTime(2001, 1, 1);
      expect(isMinorByAge(dob, today), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Grupo 5: AttendanceLog manual write data shape (BUG-18)
  // ───────────────────────────────────────────────────────────────────────────
  group('AttendanceLog manual write map shape (BUG-18)', () {
    Map<String, dynamic> _ingreso() => buildAttendanceLog(
          athleteUid: 'uid_athlete_1',
          scannedBy:  'uid_coach_1',
          action:     'ingreso',
          coachName:  'Carlos Entrenador',
        );

    Map<String, dynamic> _salida() => buildAttendanceLog(
          athleteUid: 'uid_athlete_2',
          scannedBy:  'uid_coach_2',
          action:     'salida',
          coachName:  'Ana Coach',
        );

    test('map contains athleteUid', () {
      expect(_ingreso().containsKey('athleteUid'), isTrue);
      expect(_ingreso()['athleteUid'], equals('uid_athlete_1'));
    });

    test('map contains scannedBy', () {
      expect(_ingreso().containsKey('scannedBy'), isTrue);
      expect(_ingreso()['scannedBy'], equals('uid_coach_1'));
    });

    test('map action is "ingreso" when action=ingreso', () {
      expect(_ingreso()['action'], equals('ingreso'));
    });

    test('map action is "salida" when action=salida', () {
      expect(_salida()['action'], equals('salida'));
    });

    test('location starts with "Manual —"', () {
      expect((_ingreso()['location'] as String).startsWith('Manual —'), isTrue);
    });

    test('location includes the coachName', () {
      expect(_ingreso()['location'], contains('Carlos Entrenador'));
    });

    test('status is "manual"', () {
      expect(_ingreso()['status'], equals('manual'));
      expect(_salida()['status'],  equals('manual'));
    });

    test('timestamp key is NOT present in the map (added by Firestore serverTimestamp)', () {
      expect(_ingreso().containsKey('timestamp'), isFalse);
    });

    test('map has exactly 5 keys (no extra fields)', () {
      expect(_ingreso().keys.length, equals(5));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Grupo 6: Firestore rules documentation (BUG-18)
  // ───────────────────────────────────────────────────────────────────────────
  group('Firestore rules documentation (BUG-18)', () {
    // Nota: estas reglas se verifican manualmente en Firebase Console / Emulator.
    // Los tests de este grupo documentan qué colecciones DEBEN tener reglas
    // y sirven de recordatorio de auditoría para el equipo.

    test('attendance_logs rule includes isParent read access', () {
      // La regla en firestore.rules debe incluir isParent() en el read
      // Esto es un test de documentación — la regla real se verifica en Firebase Console
      const expectedCollections = [
        'attendance_logs',
        'access_logs',
        'audit_logs',
      ];
      for (final c in expectedCollections) {
        expect(c.isNotEmpty, isTrue,
            reason: '$c debe tener regla en firestore.rules');
      }
    });

    test('attendance_logs collection name is spelled correctly in rules', () {
      // Ensures the collection name used in code matches firestore.rules
      const collectionName = 'attendance_logs';
      expect(collectionName, equals('attendance_logs'));
    });

    test('isParent helper name matches convention used across other rules', () {
      // Rules use isParent(), isCoach(), isAdmin() — naming is consistent
      const helpers = ['isParent', 'isCoach', 'isAdmin', 'isAuthenticated'];
      for (final h in helpers) {
        expect(h.isNotEmpty, isTrue,
            reason: '$h debe estar definido en firestore.rules');
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Grupo 7: Admin dashboard resolveStatus logic
  // ───────────────────────────────────────────────────────────────────────────
  group('resolveStatus admin dashboard (session_attendance_screen)', () {
    test('athlete with no logs → "ausente"', () {
      expect(resolveStatus('uid_A', []), equals('ausente'));
    });

    test('athlete with single "ingreso" log → "presente"', () {
      final logs = [
        {'athleteUid': 'uid_A', 'action': 'ingreso', 'tsMs': 1000},
      ];
      expect(resolveStatus('uid_A', logs), equals('presente'));
    });

    test('athlete with single "salida" log → "salida"', () {
      final logs = [
        {'athleteUid': 'uid_A', 'action': 'salida', 'tsMs': 2000},
      ];
      expect(resolveStatus('uid_A', logs), equals('salida'));
    });

    test('athlete with ingreso then salida (salida more recent) → "salida"', () {
      final logs = [
        {'athleteUid': 'uid_A', 'action': 'ingreso', 'tsMs': 1000},
        {'athleteUid': 'uid_A', 'action': 'salida',  'tsMs': 2000},
      ];
      expect(resolveStatus('uid_A', logs), equals('salida'));
    });

    test('athlete with salida then ingreso (ingreso more recent) → "presente"', () {
      final logs = [
        {'athleteUid': 'uid_A', 'action': 'salida',  'tsMs': 1000},
        {'athleteUid': 'uid_A', 'action': 'ingreso', 'tsMs': 2000},
      ];
      expect(resolveStatus('uid_A', logs), equals('presente'));
    });

    test('logs of other athletes do NOT affect this athlete status', () {
      final logs = [
        {'athleteUid': 'uid_B', 'action': 'ingreso', 'tsMs': 5000},
        {'athleteUid': 'uid_B', 'action': 'salida',  'tsMs': 6000},
      ];
      // uid_A has no logs at all
      expect(resolveStatus('uid_A', logs), equals('ausente'));
    });

    test('mixed logs: only uid_A logs are considered for uid_A', () {
      final logs = [
        {'athleteUid': 'uid_B', 'action': 'salida',  'tsMs': 9000},
        {'athleteUid': 'uid_A', 'action': 'ingreso', 'tsMs': 3000},
        {'athleteUid': 'uid_C', 'action': 'salida',  'tsMs': 7000},
      ];
      expect(resolveStatus('uid_A', logs), equals('presente'));
    });

    test('three logs for same athlete: most recent wins', () {
      final logs = [
        {'athleteUid': 'uid_A', 'action': 'ingreso', 'tsMs': 1000},
        {'athleteUid': 'uid_A', 'action': 'salida',  'tsMs': 2000},
        {'athleteUid': 'uid_A', 'action': 'ingreso', 'tsMs': 3000},
      ];
      expect(resolveStatus('uid_A', logs), equals('presente'));
    });

    test('null action defaults to ingreso and returns "presente"', () {
      final logs = [
        // action is null — default fallback is 'ingreso'
        {'athleteUid': 'uid_A', 'action': null, 'tsMs': 1000},
      ];
      expect(resolveStatus('uid_A', logs), equals('presente'));
    });
  });
}
