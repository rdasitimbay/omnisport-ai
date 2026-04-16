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
    print('UID Detectado: ' + jwtToken); // Modo Debug
    
    // Bypass temporal para IDs planos de Firebase (28 caracteres)
    if (jwtToken.trim().length == 28) {
      return ValidationResult(ScanStatus.apto, uid: jwtToken.trim());
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
