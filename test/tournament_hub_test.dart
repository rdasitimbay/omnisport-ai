import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:app/screens/tablas_screen.dart';
import 'package:app/services/firestore_service.dart';
import 'package:app/services/tournament_seed_data.dart';
import 'package:app/services/ai_service.dart';

void main() {
  group('TournamentSeedData Unit Tests', () {
    test('standings contains exactly 12 teams with rich details', () {
      expect(TournamentSeedData.standings.length, equals(12));
      
      for (final team in TournamentSeedData.standings) {
        expect(team.containsKey('equipo'), isTrue);
        expect(team.containsKey('puntos'), isTrue);
        expect(team.containsKey('ganados'), isTrue);
        expect(team.containsKey('empatados'), isTrue);
        expect(team.containsKey('perdidos'), isTrue);
        expect(team.containsKey('goles_favor'), isTrue);
        expect(team.containsKey('goles_contra'), isTrue);
        expect(team.containsKey('color'), isTrue);
        
        final int pts = team['puntos'];
        final int pg = team['ganados'];
        final int pe = team['empatados'];
        expect(pts, equals(pg * 3 + pe * 1));
      }
    });

    test('matches contains 18 fixtures grouped into rounds', () {
      expect(TournamentSeedData.matches.length, equals(18));
      
      for (final match in TournamentSeedData.matches) {
        expect(match.containsKey('jornada'), isTrue);
        expect(match.containsKey('fecha'), isTrue);
        expect(match.containsKey('hora'), isTrue);
        expect(match.containsKey('local'), isTrue);
        expect(match.containsKey('visitante'), isTrue);
        expect(match.containsKey('estado'), isTrue);
        
        final String state = match['estado'];
        expect(['FINALIZADO', 'LIVEMATCH', 'PROGRAMADO'].contains(state), isTrue);
      }
    });
  });

  group('AIService predictMatchOutcome Fallback Math', () {
    late AIService aiService;

    setUp(() {
      aiService = AIService();
    });

    test('calculates correct local prediction odds when offline or API fails', () async {
      final teamA = 'Dragones Volley';
      final statsA = {
        'puntos': 13,
        'partidos_jugados': 5,
        'ganados': 4,
        'empatados': 1,
        'perdidos': 0,
        'goles_favor': 15,
        'goles_contra': 4,
      };

      final teamB = 'Panteras AVP';
      final statsB = {
        'puntos': 0,
        'partidos_jugados': 5,
        'ganados': 0,
        'empatados': 0,
        'perdidos': 5,
        'goles_favor': 3,
        'goles_contra': 16,
      };

      // Since we run this offline/without active mock network, it triggers the fallback code
      final prediction = await aiService.predictMatchOutcome(teamA, statsA, teamB, statsB);

      expect(prediction.containsKey('probabilidad_teamA'), isTrue);
      expect(prediction.containsKey('probabilidad_empate'), isTrue);
      expect(prediction.containsKey('probabilidad_teamB'), isTrue);
      expect(prediction.containsKey('analisis_tactico'), isTrue);
      expect(prediction.containsKey('key_matchup'), isTrue);
      expect(prediction.containsKey('marcador_estimado'), isTrue);

      final int pA = prediction['probabilidad_teamA'];
      final int pDraw = prediction['probabilidad_empate'];
      final int pB = prediction['probabilidad_teamB'];

      expect(pA + pDraw + pB, equals(100));
      expect(pA, greaterThan(pB), reason: 'Team A has 13 points, Team B has 0 points');
    });

    test('successfully avoids division by zero when both teams have 0 points', () async {
      final teamA = 'Panteras AVP';
      final statsA = {'puntos': 0};

      final teamB = 'Nuevos AVP';
      final statsB = {'puntos': 0};

      final prediction = await aiService.predictMatchOutcome(teamA, statsA, teamB, statsB);

      final int pA = prediction['probabilidad_teamA'];
      final int pDraw = prediction['probabilidad_empate'];
      final int pB = prediction['probabilidad_teamB'];

      expect(pA + pDraw + pB, equals(100));
      expect(pA, equals(pB), reason: 'Both teams have 0 points, odds should be symmetrical');
    });
  });

  group('TablasScreen Widget Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    Widget _wrapWithMaterial(Widget child) {
      return MaterialApp(
        home: child,
      );
    }

    testWidgets('renders empty state correctly when no league data exists', (tester) async {
      await tester.pumpWidget(
        _wrapWithMaterial(
          TablasScreen(
            firestoreService: firestoreService,
            firestore: fakeFirestore,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LIGA NO INICIALIZADA'), findsOneWidget);
      expect(find.text('No hay datos del torneo registrados.'), findsOneWidget);
    });

    testWidgets('renders standings and matches correctly after seeding data', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. Seed data to fake firestore
      for (final standing in TournamentSeedData.standings) {
        await fakeFirestore.collection('tournaments').add(standing);
      }
      for (final match in TournamentSeedData.matches) {
        await fakeFirestore.collection('tournament_matches').add(match);
      }

      // 2. Render Screen
      await tester.pumpWidget(
        _wrapWithMaterial(
          TablasScreen(
            firestoreService: firestoreService,
            firestore: fakeFirestore,
          ),
        ),
      );
      await tester.pump(); // trigger stream loading
      await tester.pump(); // render list items

      // 3. Verify general structures
      expect(find.text('THE LEAGUE HUB'), findsOneWidget);
      expect(find.text('CLASIFICACIÓN'), findsOneWidget);
      expect(find.text('PARTIDOS'), findsOneWidget);
      expect(find.text('SIMULADOR IA'), findsOneWidget);

      // Verify team names render
      expect(find.text('Dragones Volley'), findsOneWidget);
      expect(find.text('Tiburones AVP'), findsOneWidget);
      expect(find.text('Panteras AVP'), findsOneWidget);

      final dynamic state = tester.state(find.byType(TablasScreen));

      // 4. Switch to Matches tab
      state.tabController.animateTo(1);
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(); // Deliver stream events to the newly built Matches tab StreamBuilder!

      // Verify that fixtures render
      expect(find.text('JORNADA 1'), findsOneWidget);
      expect(find.text('JORNADA 2'), findsOneWidget);
      expect(find.text('Cancha Central Principal'), findsWidgets);

      // 5. Switch to AI Simulator tab
      state.tabController.animateTo(2);
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(); // Deliver any necessary stream/state events to the AI tab!

      // Verify AI Simulator widgets are present
      expect(find.text('Gemini AI Predictor'), findsOneWidget);
      expect(find.text('Equipo Local'), findsOneWidget);
      expect(find.text('Equipo Visitante'), findsOneWidget);
    });
  });

  group('Multi-Disciplina Firestore & Admin Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService firestoreService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(firestore: fakeFirestore);
    });

    test('getTournamentStandings filters reactively by active sports discipline', () async {
      await fakeFirestore.collection('tournaments').add({
        'equipo': 'Búfalos Basket',
        'disciplina': 'basquetbol',
        'puntos': 12,
      });
      await fakeFirestore.collection('tournaments').add({
        'equipo': 'Dragones Volley',
        'disciplina': 'voleibol',
        'puntos': 13,
      });

      final standingsBasket = await firestoreService.getTournamentStandings(disciplina: 'basquetbol').first;
      expect(standingsBasket.docs.length, equals(1));
      expect(standingsBasket.docs.first.data()['equipo'], equals('Búfalos Basket'));

      final standingsVolley = await firestoreService.getTournamentStandings(disciplina: 'voleibol').first;
      expect(standingsVolley.docs.length, equals(1));
      expect(standingsVolley.docs.first.data()['equipo'], equals('Dragones Volley'));
    });

    test('getTournamentMatches filters reactively by active sports discipline', () async {
      await fakeFirestore.collection('tournament_matches').add({
        'local': 'Búfalos Basket',
        'visitante': 'Halcones AVP',
        'disciplina': 'basquetbol',
        'fecha': '2026-05-09',
      });
      await fakeFirestore.collection('tournament_matches').add({
        'local': 'Dragones Volley',
        'visitante': 'Panteras AVP',
        'disciplina': 'voleibol',
        'fecha': '2026-05-10',
      });

      final matchesBasket = await firestoreService.getTournamentMatches(disciplina: 'basquetbol').first;
      expect(matchesBasket.docs.length, equals(1));
      expect(matchesBasket.docs.first.data()['local'], equals('Búfalos Basket'));

      final matchesVolley = await firestoreService.getTournamentMatches(disciplina: 'voleibol').first;
      expect(matchesVolley.docs.length, equals(1));
      expect(matchesVolley.docs.first.data()['local'], equals('Dragones Volley'));
    });

    test('registerTeam adds new team under specified discipline', () async {
      await firestoreService.registerTeam(
        equipo: 'Galácticos FC',
        color: 0xFFFFE57F,
        disciplina: 'futbol',
      );

      final snap = await fakeFirestore
          .collection('tournaments')
          .where('disciplina', isEqualTo: 'futbol')
          .get();
      expect(snap.docs.length, equals(1));
      expect(snap.docs.first.data()['equipo'], equals('Galácticos FC'));
      expect(snap.docs.first.data()['puntos'], equals(0));
    });

    test('scheduleMatch adds match with correct fields', () async {
      await firestoreService.scheduleMatch(
        local: 'Galácticos FC',
        visitante: 'Deportivo AVP',
        jornada: 'Jornada 1',
        cancha: 'Estadio Principal',
        fecha: '2026-05-08',
        hora: '16:00',
        estado: 'PROGRAMADO',
        disciplina: 'futbol',
      );

      final snap = await fakeFirestore
          .collection('tournament_matches')
          .where('disciplina', isEqualTo: 'futbol')
          .get();
      expect(snap.docs.length, equals(1));
      expect(snap.docs.first.data()['local'], equals('Galácticos FC'));
      expect(snap.docs.first.data()['cancha'], equals('Estadio Principal'));
      expect(snap.docs.first.data()['estado'], equals('PROGRAMADO'));
    });
  });
}
