import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

enum ScanStatus { apto, expirado, ilegible }

class ValidationResult {
  final ScanStatus status;
  final String? uid;

  ValidationResult(this.status, {this.uid});
}

class ScannerLogic {
  static const String jwtSecret = 'omnisport_secret_2026';

  static ValidationResult validar(String jwtToken) {
    final token = jwtToken.trim();
    print('Scanned Token Trimmed: ' + token);
    
    // Bypass agnóstico: si no tiene formato JWT (3 partes con puntos), asumimos que es un UID plano
    if (!token.contains('.') || token.split('.').length != 3) {
      return ValidationResult(ScanStatus.apto, uid: token);
    }

    try {
      final jwt = JWT.verify(jwtToken, SecretKey(jwtSecret));
      final payload = jwt.payload as Map<String, dynamic>;
      
      final int period = payload['period'] as int;
      final String uid = payload['uid'] as String;
      
      final int currentPeriod = DateTime.now().millisecondsSinceEpoch ~/ 30000;
      
      // Tolerancia: ± 1 periodo (90s total window)
      if ((currentPeriod - period).abs() > 1) {
        return ValidationResult(ScanStatus.expirado);
      }

      return ValidationResult(ScanStatus.apto, uid: uid);
    } catch (e) {
      return ValidationResult(ScanStatus.ilegible);
    }
  }
}
