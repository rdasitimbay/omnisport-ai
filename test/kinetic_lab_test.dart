import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/screens/velocity_kinetic/kinetic_lab_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('es'),
      home: child,
    );

void _setTallViewport(WidgetTester t) {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1.0;
}

void main() {
  group('KineticLabScreen Widget Tests', () {
    testWidgets('renders KineticLabScreen editorial headers and base stats', (WidgetTester tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const KineticLabScreen(
        athleteId: 'athlete_test_123',
        athleteName: 'Juan Pérez',
        sport: 'Voleibol',
      )));

      // Allow animations and tickers to frame
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify the asymmetric editorial headers exist
      expect(find.text('RENDIMIENTO PRO'), findsOneWidget);
      expect(find.text('Kinetic Lab'), findsOneWidget);

      // Verify bento biometric grid cards exist
      expect(find.text('CARDIO'), findsOneWidget);
      expect(find.text('POTENCIA'), findsOneWidget);
      expect(find.text('ACELERACIÓN'), findsOneWidget);
    });

    testWidgets('interacts with cardio pulse simulation buttons', (WidgetTester tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const KineticLabScreen(
        athleteId: 'athlete_test_123',
        athleteName: 'Juan Pérez',
        sport: 'Voleibol',
      )));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initial BPM is 124
      expect(find.text('124'), findsOneWidget);

      // Tap 'Subir ritmo' button
      await tester.tap(find.text('Subir ritmo'));
      await tester.pump();

      // BPM increases by 15 -> 139
      expect(find.text('139'), findsOneWidget);

      // Tap 'Calmar' button
      await tester.tap(find.text('Calmar'));
      await tester.pump();

      // BPM decreases by 15 -> 124
      expect(find.text('124'), findsOneWidget);
    });

    testWidgets('displays kinetic energy calculation dynamically', (WidgetTester tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const KineticLabScreen(
        athleteId: 'athlete_test_123',
        athleteName: 'Juan Pérez',
        sport: 'Voleibol',
      )));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check for Kinetic Simulator header
      expect(find.text('SIMULADOR CINÉTICO'), findsOneWidget);
      expect(find.text('Cálculo de Energía de Ejecución'), findsOneWidget);

      // Double check kinetic energy calculation text
      // Ec = 0.5 * 72 * 1.6^2 = 36 * 2.56 = 92.16 -> 92 J
      expect(find.text('92'), findsOneWidget);
    });

    testWidgets('renders Gemini AI telemetric analysis engine', (WidgetTester tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const KineticLabScreen(
        athleteId: 'athlete_test_123',
        athleteName: 'Juan Pérez',
        sport: 'Voleibol',
      )));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('GEMINI PERFORMANCE ENGINE'), findsOneWidget);
      expect(find.text('AI Biometric Review'), findsOneWidget);
      expect(find.text('ANALIZAR TELEMETRÍA'), findsOneWidget);
    });
  });
}
