import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/screens/pizarra_tactica_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: child,
    );

void main() {
  group('PizarraTacticaScreen', () {
    testWidgets('renders without crash', (tester) async {
      await tester.pumpWidget(_wrap(const PizarraTacticaScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(PizarraTacticaScreen), findsOneWidget);
    });

    testWidgets('displays team player tokens and ball', (tester) async {
      await tester.pumpWidget(_wrap(const PizarraTacticaScreen()));
      await tester.pumpAndSettle();

      // We have 6 Blue Team players (C1, O2, C3, P4, P5, L6)
      // 6 Red Team players (1, 2, 3, 4, 5, 6)
      // 1 Ball (⚽)
      expect(find.text('C1'), findsOneWidget);
      expect(find.text('O2'), findsOneWidget);
      expect(find.text('C3'), findsOneWidget);
      expect(find.text('P4'), findsOneWidget);
      expect(find.text('P5'), findsOneWidget);
      expect(find.text('L6'), findsOneWidget);

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);

      expect(find.text('⚽'), findsOneWidget);
    });

    testWidgets('toggles tools between Mover and Dibujar', (tester) async {
      await tester.pumpWidget(_wrap(const PizarraTacticaScreen()));
      await tester.pumpAndSettle();

      // Find the "Dibujar" button and tap it
      final dibujarBtn = find.text('Dibujar');
      expect(dibujarBtn, findsOneWidget);

      await tester.tap(dibujarBtn);
      await tester.pumpAndSettle();
    });
  });
}
