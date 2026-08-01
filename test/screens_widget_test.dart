/// Widget regression tests for key screens.
///
/// Covers screens that can be rendered without live Firebase:
///   - OnboardingScreen: consent logic, proceed guard, page navigation
///   - SosAlertScreen: red button flow, injury selector, send guard
///   - LanguagePicker: renders and shows both language options
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:app/screens/onboarding_screen.dart';
import 'package:app/screens/sos_alert_screen.dart';
import 'package:app/screens/language_picker_screen.dart';
import 'package:app/services/preferences_service.dart';
import 'package:app/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es'), Locale('en')],
      home: child,
    );

/// Advances one frame then 400ms — covers PageView 300ms animation.
Future<void> _advance(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// Pump frames without needing settle (safe for looping animations).
Future<void> _frames(WidgetTester t) =>
    t.pump(const Duration(milliseconds: 300));

/// Set a tall test viewport so SingleChildScrollView content is reachable.
void _setTallViewport(WidgetTester t) {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// LanguagePickerScreen
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  group('LanguagePickerScreen', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService().init();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpWidget(_wrap(const LanguagePickerScreen()));
      await _advance(tester);
      expect(find.byType(LanguagePickerScreen), findsOneWidget);
    });

    testWidgets('displays Español and English options', (tester) async {
      await tester.pumpWidget(_wrap(const LanguagePickerScreen()));
      await _advance(tester);
      expect(find.textContaining('Español'), findsWidgets);
      expect(find.textContaining('English'), findsWidgets);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // OnboardingScreen
  // ─────────────────────────────────────────────────────────────────────────
  group('OnboardingScreen', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService().init();
    });

    testWidgets('renders first slide without crash', (tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('shows Siguiente button on first slide', (tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);
      expect(find.widgetWithText(ElevatedButton, 'Siguiente'), findsOneWidget);
    });

    testWidgets('shows skip button (Saltar) on first slide', (tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);
      expect(find.text('Saltar'), findsOneWidget);
    });

    testWidgets('shows 4 progress dots', (tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);
      expect(find.byType(AnimatedContainer), findsNWidgets(4));
    });

    testWidgets('navigates to slide 2 via Siguiente', (tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
      await _advance(tester);

      // Still inside the onboarding flow
      expect(find.byType(OnboardingScreen), findsOneWidget);
      // Siguiente still present (not on last slide)
      expect(find.widgetWithText(ElevatedButton, 'Siguiente'), findsOneWidget);
    });

    testWidgets('navigates to consent slide after 3 taps', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
        await _advance(tester);
      }

      // Consent slide header is visible
      expect(find.text('Consentimiento LOPDP'), findsOneWidget);
    });

    testWidgets('consent slide shows 3 Checkboxes', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
        await _advance(tester);
      }

      expect(find.byType(Checkbox), findsNWidgets(3));
    });

    testWidgets('proceed button disabled before consents', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
        await _advance(tester);
      }

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Aceptar y Empezar'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('proceed button enables after all 3 consents', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
        await _advance(tester);
      }

      // Tap each consent card by title (InkWell covers the whole card)
      for (final title in [
        'Datos personales y deportivos',
        'Datos de salud y médicos',
        'Notificaciones al tutor',
      ]) {
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await _frames(tester);
      }

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Aceptar y Empezar'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('skip button hidden on consent slide', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await _advance(tester);

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
        await _advance(tester);
      }

      expect(find.text('Saltar'), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SosAlertScreen
  //
  // AnimationController.repeat(reverse:true) never settles — use _frames()
  // not pumpAndSettle(). Viewport set to 1600px tall so the injury grid,
  // description field, and Cancelar button are all reachable.
  // ─────────────────────────────────────────────────────────────────────────
  group('SosAlertScreen', () {
    Widget _sos({String uid = 'uid_test', String name = 'Juan Pérez'}) =>
        _wrap(SosAlertScreen(athleteUid: uid, athleteName: name));

    setUp(() {});

    testWidgets('renders red SOS button on initial state', (tester) async {
      await tester.pumpWidget(_sos());
      await _frames(tester);
      expect(find.text('S.O.S'), findsOneWidget);
    });

    testWidgets('shows athlete name in uppercase', (tester) async {
      await tester.pumpWidget(_sos(name: 'Carlos Vera'));
      await _frames(tester);
      expect(find.text('CARLOS VERA'), findsOneWidget);
    });

    testWidgets('shows long-press instruction text', (tester) async {
      await tester.pumpWidget(_sos());
      await _frames(tester);
      expect(find.text('Mantener presionado para activar'), findsOneWidget);
    });

    testWidgets('AppBar shows S.O.S MÉDICO title', (tester) async {
      await tester.pumpWidget(_sos());
      await _frames(tester);
      expect(find.text('S.O.S MÉDICO'), findsOneWidget);
    });

    testWidgets('long press on SOS button reveals injury selector', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_sos());
      await _frames(tester);

      await tester.longPress(find.text('S.O.S'));
      await _frames(tester);

      expect(find.text('¿Qué tipo de lesión?'), findsOneWidget);
    });

    testWidgets('injury selector shows all 8 injury type labels', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_sos());
      await _frames(tester);

      await tester.longPress(find.text('S.O.S'));
      await _frames(tester);

      for (final injury in InjuryType.values) {
        expect(find.text(injury.label), findsOneWidget,
            reason: '${injury.label} not found in selector');
      }
    });

    testWidgets('send button disabled before selecting injury', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_sos());
      await _frames(tester);

      await tester.longPress(find.text('S.O.S'));
      await _frames(tester);

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ENVIAR ALERTA S.O.S'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('send button enables after selecting an injury', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_sos());
      await _frames(tester);

      await tester.longPress(find.text('S.O.S'));
      await _frames(tester);

      await tester.tap(find.text(InjuryType.contusion.label));
      await _frames(tester);

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ENVIAR ALERTA S.O.S'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('cancel returns to SOS red button screen', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_sos());
      await _frames(tester);

      await tester.longPress(find.text('S.O.S'));
      await _frames(tester);

      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await _frames(tester);

      expect(find.text('S.O.S'), findsOneWidget);
      expect(find.text('¿Qué tipo de lesión?'), findsNothing);
    });

    testWidgets('selecting a second injury keeps send button enabled', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_sos());
      await _frames(tester);

      await tester.longPress(find.text('S.O.S'));
      await _frames(tester);

      await tester.tap(find.text(InjuryType.contusion.label));
      await _frames(tester);
      await tester.tap(find.text(InjuryType.esguince.label));
      await _frames(tester);

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ENVIAR ALERTA S.O.S'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('description TextField is present in injury selector', (tester) async {
      _setTallViewport(tester);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_sos());
      await _frames(tester);

      await tester.longPress(find.text('S.O.S'));
      await _frames(tester);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == 'Descripción breve (opcional)',
        ),
        findsOneWidget,
      );
    });
  });
}
