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
      'full_name': 'David Morales',
      'teamOrCategory': 'Sub 18',
      'status': 'Al día',
      'isMinor': false,
      'photoUrl': '',
    });

    await _pumpScanner(tester);

    // 2. Simulamos la detección con el UID plano (Bypass de ScannerLogic)
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    await state.simularDeteccion('uid_apto');
    await tester.pump();                             // rebuild con success state + subscribe StreamBuilder
    await tester.pump();                             // StreamBuilder recibe snapshot → renderiza datos

    // 4. Verificamos UI
    expect(find.text('DAVID'), findsOneWidget);
    expect(find.text('ACCESO AUTORIZADO / AL DÍA'), findsOneWidget);

    // Drenar el timer de 3s de _setSuccess para que el test no quede con timers pendientes
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Flujo 2: Pago Pendiente (Naranja)', (WidgetTester tester) async {
    await fakeFirestore.collection('athletes').doc('uid_pago').set({
      'full_name': 'Carlos Perez',
      'teamOrCategory': 'Sub 20',
      'status': 'Pago pendiente',
      'isMinor': false,
      'photoUrl': '',
    });

    await _pumpScanner(tester);
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    await state.simularDeteccion('uid_pago');
    await tester.pump();
    await tester.pump();

    expect(find.text('CARLOS'), findsOneWidget);
    expect(find.text('PAGO PENDIENTE'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Flujo 3: Acceso Denegado (Rojo)', (WidgetTester tester) async {
    await fakeFirestore.collection('athletes').doc('uid_denegado').set({
      'full_name': 'Ana Lopez',
      'teamOrCategory': 'Mayores',
      'status': 'Membresía Vencida',
      'isMinor': false,
      'photoUrl': '',
    });

    await _pumpScanner(tester);
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    await state.simularDeteccion('uid_denegado');
    await tester.pump();
    await tester.pump();

    expect(find.text('ANA'), findsOneWidget);
    expect(find.text('ACCESO DENEGADO'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Flujo 4: Atleta Menor de Edad (Flujo Tutor)', (WidgetTester tester) async {
    await fakeFirestore.collection('athletes').doc('uid_menor').set({
      'full_name': 'Luisito Perez',
      'teamOrCategory': 'Sub 15',
      'status': 'Al día',
      'isMinor': true, // Activa flujo menor
      'photoUrl': '',
    });

    await _pumpScanner(tester);
    final dynamic state = tester.state(find.byType(QrScannerScreen));
    await state.simularDeteccion('uid_menor');
    await tester.pump();
    await tester.pump();

    // Debe mostrar que espera al tutor (mensaje en la parte superior)
    expect(find.textContaining('Menor de Edad'), findsWidgets);

    // Simulamos el 2do escaneo (Tutor autoriza)
    await state.simularDeteccion('uid_tutor_generico');
    await tester.pump();
    await tester.pump();

    // Estado success: el card del atleta menor muestra su nombre + status verde
    expect(find.text('LUISITO'), findsOneWidget);
    expect(find.text('ACCESO AUTORIZADO / AL DÍA'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });
}
