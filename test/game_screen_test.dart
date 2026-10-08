import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/ui/game_screen.dart';

import 'support/fakes.dart';

void main() {
  Future<void> pumpGame(WidgetTester tester, c) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: c)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  group('A-20 one run, one result', () {
    testWidgets('double tap on "No thanks" applies the run once',
        (tester) async {
      final c = makeController(ads: FakeAds(ready: true));
      await pumpGame(tester, c);
      gameOf(tester).session!.rawCrystals = 7;
      await crashNow(tester);
      expect(gameOf(tester).phase.value, RunPhase.crashed);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('CONTINUE?'), findsOneWidget);

      // Two taps inside one frame: both reach the button before it rebuilds.
      await tester.tap(find.text('No thanks'));
      await tester.tap(find.text('No thanks'));
      await tester.pump(const Duration(seconds: 1));

      expect(c.progress.runs, 1);
      expect(c.progress.crystals, 7);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
    });

    testWidgets('countdown ending as the player taps applies the run once',
        (tester) async {
      final c = makeController(ads: FakeAds(ready: true));
      await pumpGame(tester, c);
      gameOf(tester).session!.rawCrystals = 3;
      await crashNow(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('CONTINUE?'), findsOneWidget);

      // Let the countdown reach its last second, then tap "No thanks" just
      // before it hits 0 and let it hit 0 too.
      await tester.pump(const Duration(milliseconds: 3900));
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('No thanks'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));

      expect(c.progress.runs, 1);
      expect(c.progress.crystals, 3);
    });
  });

  group('FEEL-03 / A-07 back guard', () {
    Future<void> pushGame(WidgetTester tester, c) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => GameScreen(controller: c))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 16));
    }

    testWidgets('back mid-run saves the run and shows results',
        (tester) async {
      final c = makeController();
      await pushGame(tester, c);
      final g = gameOf(tester);
      g.tapInput();
      g.session!.rawCrystals = 5;
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.phase.value, RunPhase.playing);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(GameScreen), findsOneWidget); // still here
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(c.progress.runs, 1);
      expect(c.progress.crystals, 5);

      // On the results screen, back leaves as normal.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
      expect(c.progress.runs, 1);
    });

    testWidgets('back while crashed (revive offer) also saves the run',
        (tester) async {
      final c = makeController(ads: FakeAds(ready: true));
      await pushGame(tester, c);
      await crashNow(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('CONTINUE?'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('CONTINUE?'), findsNothing);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(c.progress.runs, 1);
    });

    testWidgets('back before the first tap just leaves', (tester) async {
      final c = makeController();
      await pushGame(tester, c);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
      expect(c.progress.runs, 0);
    });
  });
}
