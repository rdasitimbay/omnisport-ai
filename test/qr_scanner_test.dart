import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:app/screens/qr_scanner_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
    await Hive.openBox('offline_logs');
  });

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  Future<void> _pumpScanner(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrScannerScreen(firestore: fakeFirestore, isTestMode: true),
      ),
    );
  }

  testWidgets('Flujo 1: Acceso Autorizado / Al Día (Verde)', (WidgetTester tester) async {
    // 1. Setup Data
    await fakeFirestore.collection('athletes').doc('uid_apto').set({
      'fullName': 'David Morales',
      'teamOrCategory': 'Sub 18',
      'status': 'Al día',
      'isMinor': false,
      'photoUrl': '',
    });

    await _pumpScanner(tester);

    // 2. Simulamos la detección con el UID plano (Bypass de ScannerLogic)
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    await state.simularDeteccion('uid_apto');
    
    // 3. Esperamos el delay del skeleton (600ms + renderizado)
    await tester.pump(const Duration(seconds: 2));

    // 4. Verificamos UI
    expect(find.text('DAVID'), findsOneWidget);
    expect(find.text('ACCESO AUTORIZADO / AL DÍA'), findsOneWidget);
  });

  testWidgets('Flujo 2: Pago Pendiente (Naranja)', (WidgetTester tester) async {
    await fakeFirestore.collection('athletes').doc('uid_pago').set({
      'fullName': 'Carlos Perez',
      'teamOrCategory': 'Sub 20',
      'status': 'Pago pendiente',
      'isMinor': false,
      'photoUrl': '',
    });

    await _pumpScanner(tester);
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    await state.simularDeteccion('uid_pago');
    
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('CARLOS'), findsOneWidget);
    expect(find.text('PAGO PENDIENTE'), findsOneWidget);
  });

  testWidgets('Flujo 3: Acceso Denegado (Rojo)', (WidgetTester tester) async {
    await fakeFirestore.collection('athletes').doc('uid_denegado').set({
      'fullName': 'Ana Lopez',
      'teamOrCategory': 'Mayores',
      'status': 'Membresía Vencida',
      'isMinor': false,
      'photoUrl': '',
    });

    await _pumpScanner(tester);
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    await state.simularDeteccion('uid_denegado');
    
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('ANA'), findsOneWidget);
    expect(find.text('ACCESO DENEGADO'), findsOneWidget);
  });

  testWidgets('Flujo 4: Atleta Menor de Edad (Flujo Tutor)', (WidgetTester tester) async {
    await fakeFirestore.collection('athletes').doc('uid_menor').set({
      'fullName': 'Luisito Perez',
      'teamOrCategory': 'Sub 15',
      'status': 'Al día',
      'isMinor': true, // Activa flujo menor
      'photoUrl': '',
    });

    await _pumpScanner(tester);
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    await state.simularDeteccion('uid_menor');
    
    await tester.pump(const Duration(seconds: 2));

    // Debe mostrar que espera al tutor, y no muestra el perfil final aún
    expect(find.textContaining('Menor de Edad'), findsOneWidget);
    
    // Simulamos el 2do escaneo (Tutor autoriza)
    await state.simularDeteccion('uid_tutor_generico');
    await tester.pump(const Duration(seconds: 2));
    
    expect(find.textContaining('Match Completado'), findsOneWidget);
  });
}
