import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/game/haptics.dart';
import 'package:probe_dash/game/probe_game.dart';
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

  group('FEEL-11 / A-06 screen fit', () {
    testWidgets('HUD starts below a 48 dp top inset', (tester) async {
      final c = makeController();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(top: 48),
              padding: const EdgeInsets.only(top: 48)),
          child: child!,
        ),
        home: GameScreen(controller: c),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      expect(gameOf(tester).hudTop, greaterThanOrEqualTo(48));
    });

    testWidgets('HUD without insets keeps its 5% top margin', (tester) async {
      final c = makeController();
      await pumpGame(tester, c);
      final g = gameOf(tester);
      expect(g.hudTop, closeTo(g.size.y * 0.05, 1e-9));
    });

    test('hudTopFor picks the larger of 5% height and inset + 8', () {
      expect(ProbeGame.hudTopFor(0, 800), 40);
      expect(ProbeGame.hudTopFor(48, 800), 56);
    });

    testWidgets('immersive mode on enter, edge-to-edge on leave',
        (tester) async {
      final modes = <Object?>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final c = makeController();
      await pumpGame(tester, c);
      expect(modes, ['SystemUiMode.immersiveSticky']);
      await tester.pumpWidget(const SizedBox());
      expect(modes, ['SystemUiMode.immersiveSticky', 'SystemUiMode.edgeToEdge']);
    });
  });

  group('FEEL-07 haptics', () {
    late List<Object?> vibrations;

    setUp(() => vibrations = []);

    Future<void> listen(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          vibrations.add(call.arguments);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
    }

    testWidgets('crash gives one heavy impact', (tester) async {
      await listen(tester);
      await pumpGame(tester, makeController());
      await crashNow(tester);
      expect(vibrations, ['HapticFeedbackType.heavyImpact']);
    });

    testWidgets('the one switch turns haptics off', (tester) async {
      await listen(tester);
      Haptics.enabled = false;
      addTearDown(() => Haptics.enabled = true);
      await pumpGame(tester, makeController());
      await crashNow(tester);
      expect(vibrations, isEmpty);
    });
  });

  group('A-04 best-distance chase', () {
    test('HUD best line', () {
      expect(ProbeGame.bestLine(0, passed: false), isNull);
      expect(ProbeGame.bestLine(1287, passed: false), 'BEST 1287 m');
      expect(ProbeGame.bestLine(1287, passed: true), 'NEW BEST');
    });

    test('banner grows 0.6x to 1x in 150 ms, holds, fades by 1.25 s', () {
      expect(ProbeGame.bannerScale(0), closeTo(0.6, 1e-9));
      expect(ProbeGame.bannerScale(0.15), 1.0);
      expect(ProbeGame.bannerAlpha(0.9), 1.0);
      expect(ProbeGame.bannerAlpha(1.1), closeTo(0.5, 1e-9));
      expect(ProbeGame.bannerAlpha(1.25), closeTo(0, 1e-9));
      expect(ProbeGame.bannerAlpha(2), 0);
    });

    testWidgets('passing the best shows the NEW BEST! banner once',
        (tester) async {
      final c = makeController(best: 5);
      await pumpGame(tester, c);
      final g = gameOf(tester);
      g.tapInput();
      g.session!.invincibleSeconds = 1e9;
      expect(g.newBestBannerAge, isNull);
      for (var i = 0; i < 30 && !g.session!.passedBest; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(g.session!.passedBest, isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      expect(g.newBestBannerAge, isNotNull);
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(g.newBestBannerAge, isNull); // gone after ~1.25 s
    });
  });

  group('FEEL-08 probe visible while invincible', () {
    test('blink never hides the probe', () {
      for (var t = 0.0; t < 2; t += 0.01) {
        final o = ProbeGame.probeOpacity(t, invincible: true);
        expect(o, greaterThanOrEqualTo(ProbeGame.blinkOffOpacity));
      }
      expect(ProbeGame.probeOpacity(0.05, invincible: true), 0.35);
      expect(ProbeGame.probeOpacity(0.15, invincible: true), 1.0);
      expect(ProbeGame.probeOpacity(0.05, invincible: false), 1.0);
    });
  });
}
