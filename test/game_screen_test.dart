import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/services/ad_service.dart';
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
      await waitForOverlay(tester);
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
      await waitForOverlay(tester);
      expect(find.text('CONTINUE?'), findsOneWidget);

      // Let the countdown reach its last second, then tap "No thanks" just
      // before it hits 0 and let it hit 0 too.
      // (The offer has been up for 500 ms at this point.)
      await tester.pump(const Duration(milliseconds: 4300));
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('No thanks'));
      await tester.pump(const Duration(milliseconds: 300));
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
      await waitForOverlay(tester);
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

  group('FEEL-01 / A-01 crash beat and input lock', () {
    testWidgets('overlay waits for the crash beat, then ignores early taps',
        (tester) async {
      final ads = FakeAds(ready: true);
      final c = makeController(ads: ads);
      await pumpGame(tester, c);
      await crashNow(tester);
      expect(gameOf(tester).phase.value, RunPhase.crashed);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('CONTINUE?'), findsNothing);
      await tester.pump(const Duration(milliseconds: 150)); // 550 ms
      expect(find.text('CONTINUE?'), findsOneWidget);

      // 100 ms after the panel appears: taps on both buttons do nothing.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('No thanks'), warnIfMissed: false);
      await tester.tap(find.text('Watch ad to revive'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('CONTINUE?'), findsOneWidget);
      expect(c.progress.runs, 0);
      expect(ads.rewardedShown, 0);

      // After the 400 ms lock the same tap works.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('No thanks'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(c.progress.runs, 1);
    });

    testWidgets('results panel ignores a tap on PLAY AGAIN at first',
        (tester) async {
      final c = makeController(); // no revive possible: results after beat
      await pumpGame(tester, c);
      await crashNow(tester);
      gameOf(tester).session!.reviveUsed = true;
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('PLAY AGAIN'), findsOneWidget);

      await tester.tap(find.text('PLAY AGAIN'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('PLAY AGAIN'), findsOneWidget); // still on results
      expect(gameOf(tester).phase.value, RunPhase.over);
    });
  });

  group('A-08 / A-09 no-ad path and live ad state', () {
    testWidgets('ads disabled: crash goes straight to results, no offer',
        (tester) async {
      final c = makeController(ads: AdService(enabled: false));
      await pumpGame(tester, c);
      gameOf(tester).session!.rawCrystals = 2;
      await crashNow(tester);
      expect(gameOf(tester).session!.canRevive, isTrue); // revive unused
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PLAY AGAIN'), findsNothing); // still in the beat
      await waitForOverlay(tester);
      expect(find.text('CONTINUE?'), findsNothing);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(find.text('No ad available'), findsOneWidget); // AD-4 fallback
      expect(c.progress.runs, 1);
    });

    testWidgets('2× button switches on when an ad finishes loading',
        (tester) async {
      final ads = FakeAds(ready: true);
      final c = makeController(ads: ads);
      await pumpGame(tester, c);
      gameOf(tester).session!
        ..rawCrystals = 4
        ..reviveUsed = true; // no revive: results right after the beat
      await crashNow(tester);
      ads.ready = false;
      await waitForOverlay(tester);
      expect(find.text('No ad available'), findsOneWidget);

      ads.ready = true;
      await tester.pump();
      expect(find.text('No ad available'), findsNothing);
      final button = find.ancestor(
          of: find.text('Watch ad: 2× crystals'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      expect(tester.widget<ButtonStyleButton>(button).enabled, isTrue);
    });

    testWidgets('revive button follows the ad state while offered',
        (tester) async {
      final ads = FakeAds(ready: true);
      final c = makeController(ads: ads);
      await pumpGame(tester, c);
      await crashNow(tester);
      await waitForOverlay(tester);
      expect(find.text('Watch ad to revive'), findsOneWidget);

      ads.ready = false;
      await tester.pump();
      expect(find.text('No ad available'), findsOneWidget);
      ads.ready = true;
      await tester.pump();
      expect(find.text('Watch ad to revive'), findsOneWidget);
    });
  });
}
