import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:app/utils/scanner_logic.dart';
import 'package:app/screens/qr_scanner_screen.dart';

class DPOShieldWrapper {
  static String generateMockToken({required int offsetSeconds}) {
    final currentPeriod = DateTime.now().millisecondsSinceEpoch ~/ 30000;
    
    int period = currentPeriod;
    // Forzamos el salto de periodo para simular expiración realista (+ de 30 seg = 2 periodos mínimo por la tolerancia)
    if (offsetSeconds <= -30) {
      period = currentPeriod - 2; 
    }
    
    final jwtToken = JWT({'uid': 'test', 'period': period});
    return jwtToken.sign(SecretKey(ScannerLogic.jwtSecret));
  }
}

void main() {
  group('Pruebas Unitarias - Validación de Acceso (Sprint 1)', () {
    
    test('Caso 1: QR Válido y Vigente -> Debe permitir el ingreso', () {
      // Simulamos un token generado hace 5 segundos (Válido por 30s)
      final tokenValido = DPOShieldWrapper.generateMockToken(offsetSeconds: -5);
      final resultado = ScannerLogic.validar(tokenValido);
      
      expect(resultado.status, ScanStatus.apto);
    });

    test('Caso 2: QR Expirado (>30s) -> Debe denegar por seguridad', () {
      // Simulamos un token generado hace 40 segundos
      final tokenExpirado = DPOShieldWrapper.generateMockToken(offsetSeconds: -40);
      final resultado = ScannerLogic.validar(tokenExpirado);
      
      expect(resultado.status, ScanStatus.expirado);
    });

    test('Caso 3: Código Falso/Ilegible -> Debe detectar fraude', () {
      const codigoBasura = "https://hack-omnisport.com/fake-access";
      final resultado = ScannerLogic.validar(codigoBasura);
      
      expect(resultado.status, ScanStatus.ilegible);
    });
  });

  testWidgets('Caso 4: Reintento en Android -> Estado vuelve a scanning', (tester) async {
    // Esta prueba simula la lógica inyectada para resetear el escáner (incluyendo start())
    await tester.pumpWidget(const MaterialApp(home: QrScannerScreen()));
    final state = tester.state(find.byType(QrScannerScreen));
    
    // Procesar deteccion basura para invocar _setInvalid
    // _setInvalid lanza un Future.delayed de 2 segundos y luego llama a _resetScanner
    await (state as dynamic).simularDeteccion("fake_qr_to_trigger_reset");
    
    // Verificamos que inmediatamente la UI muestre el error
    await tester.pump();
    expect(find.text('Código QR Ilegible o Falso'), findsOneWidget);

    // Simulamos el paso de los 2 segundos del delay interno
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    
    // Después del _resetScanner(), la interfaz debe volver a pedir el pase
    // Lo que confirma que la UI y el flag de "isProcessing" se restablecieron (Android reintento)
    expect(find.text('Escanea el pase del Atleta'), findsOneWidget);
  });
}
