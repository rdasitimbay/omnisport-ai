import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:app/utils/scanner_logic.dart';
import 'package:app/screens/qr_scanner_screen.dart';

class MockGenerator {
  static String createToken({required int exp}) {
    // exp en segundos
    final jwt = JWT({'uid': 'test_athlete_123', 'period': (DateTime.now().millisecondsSinceEpoch ~/ 30000) + exp ~/ 30});
    return jwt.sign(SecretKey(ScannerLogic.jwtSecret));
  }
}

void main() {
  group('Pruebas de Validación DPO Shield', () {
    test('Debe retornar APTO para un JWT válido y vigente', () {
      final qrValido = MockGenerator.createToken(exp: 15); // Dentro de la ventana (± 30s)
      final resultado = ScannerLogic.validar(qrValido);
      expect(resultado.status, ScanStatus.apto);
    });

    test('Debe retornar ILEGIBLE para un código que no es JWT', () {
      final qrFalso = "https://google.com";
      final resultado = ScannerLogic.validar(qrFalso);
      expect(resultado.status, ScanStatus.ilegible);
    });

    test('Debe retornar EXPIRADO para un token expirado o adelantado', () {
      // Periodo viejo
      final jwtVy = JWT({'uid': 'viejo', 'period': (DateTime.now().millisecondsSinceEpoch ~/ 30000) - 2});
      final qrViejo = jwtVy.sign(SecretKey(ScannerLogic.jwtSecret));

      final resultado = ScannerLogic.validar(qrViejo);
      expect(resultado.status, ScanStatus.expirado);
    });
  });

  testWidgets('Scanner muestra overlay rojo ante código falso u obsoleto', (tester) async {
    // Montamos la aplicación con el Scanner sin Firebase (ya que para el código falso fallará antes de llegar a Firebase)
    await tester.pumpWidget(const MaterialApp(home: QrScannerScreen()));
    
    // El widget debe montarse correctamente
    expect(find.byType(QrScannerScreen), findsOneWidget);

    // Obtenemos el state de QrScannerScreen para simular la detección (hemos expuesto un método)
    final state = tester.state(find.byType(QrScannerScreen));
    
    // Simulamos una detección falsa iterando el ciclo de vida
    await (state as dynamic).simularDeteccion("codigo_basura");
    await tester.pump();

    // Verificamos que aparezca el mensaje de error o falso
    expect(find.text('Código QR Ilegible o Falso'), findsOneWidget);

    // Agotamos el timer de limpieza de 2 segundos para que el test libere los frame de animación
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}
