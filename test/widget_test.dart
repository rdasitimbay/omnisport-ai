import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app/screens/splash_screen.dart';
import 'package:app/services/preferences_service.dart';
import 'package:app/l10n/app_localizations.dart';

void main() {
  testWidgets('Splash Screen smoke test - verifies rendering and branding text', (WidgetTester tester) async {
    // Initialize SharedPreferences mock
    SharedPreferences.setMockInitialValues({});
    await PreferencesService().init();

    // Pump SplashScreen inside a MaterialApp with proper translation delegates
    await tester.pumpWidget(const MaterialApp(
      home: SplashScreen(),
      localizationsDelegates: [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [Locale('es', ''), Locale('en', '')],
    ));

    // Allow asynchronous localizations loading to complete and mount SplashScreen
    await tester.pump();

    // Verify that SplashScreen mounts and shows the branding text
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('POWERED BY ROMMEL ASITIMBAY MORALES'), findsOneWidget);

    // Allow the routing delay timer to complete and execute navigation
    await tester.pumpAndSettle(const Duration(seconds: 3));

  });
}




