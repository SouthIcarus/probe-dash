// Spec v2 US-5 / AD-5 to AD-9 / GAME-4 through the Results screen (plan
// step A-4), including the late-ad guard (decision S2).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/app/game_controller.dart';
import 'package:probe_dash/logic/ad_rules.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/services/ad_service.dart';
import 'package:probe_dash/ui/game_screen.dart';

import 'support/fakes.dart';

void main() {
  late DateTime now;
  setUp(() => now = DateTime.utc(2026, 10, 9, 12));

  /// Controller whose next run is [nextRun], with a fresh interstitial
  /// loaded that appears 300 ms after the show call and stays [adUp].
  (GameController, FakeAds) rig({
    int nextRun = 6,
    Duration? appearsAfter = const Duration(milliseconds: 300),
    Duration? adUp = const Duration(seconds: 5),
    bool removeAds = false,
    DateTime? lastShownAt,
    bool rewardedWatched = false,
  }) {
    final ads = FakeAds(ready: true, watchResult: rewardedWatched)
      ..loadedInterstitialAge = const Duration(minutes: 1)
      ..interstitialScript =
          InterstitialScript(appearsAfter: appearsAfter, dismissAfter: adUp);
    final c = makeController(
      crystals: 120, // the upgrade shortcut shows too
      runs: nextRun - 1,
      removeAds: removeAds,
      lastInterstitialAt: lastShownAt,
      ads: ads,
      clock: () => now,
    );
    return (c, ads);
  }

  /// Opens the game from a Home-like page so back can leave it.
  Future<void> pushGame(WidgetTester tester, GameController c) async {
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

  /// Ends the current run with no revive offer; Results opens 500 ms later
  /// (crash beat). Returns with Results just opened.
  Future<void> endRun(WidgetTester tester, {int crystals = 5}) async {
    gameOf(tester).session!
      ..rawCrystals = crystals
      ..reviveUsed = true;
    await crashNow(tester);
    await tester.pump(const Duration(milliseconds: 500)); // Results-open
    expect(find.text('PLAY AGAIN'), findsOneWidget);
  }

  ButtonStyleButton button(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.textContaining(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));

  void expectAllDisabled(WidgetTester tester) {
    for (final label in [
      'PLAY AGAIN',
      'Home',
      'Upgrades',
      'Upgrade:',
      'Watch ad: 2× crystals',
    ]) {
      expect(button(tester, label).enabled, isFalse, reason: label);
    }
  }

  void expectAllEnabled(WidgetTester tester) {
    for (final label in [
      'PLAY AGAIN',
      'Home',
      'Upgrades',
      'Upgrade:',
      'Watch ad: 2× crystals',
    ]) {
      expect(button(tester, label).enabled, isTrue, reason: label);
    }
  }

  Future<void> tapPlayAgain(WidgetTester tester) async {
    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  group('US-5 happy path and AD-8 lock', () {
    testWidgets('run 6: ad over Results; taps and back ignored; after close '
        'one tap reaches Ready in < 1 s, no second ad', (tester) async {
      final (c, ads) = rig();
      await pushGame(tester, c);
      await endRun(tester);
      expect(ads.interstitialShowCalls, 1); // as Results opens
      expect(c.progress.runs, 6);
      expectAllDisabled(tester);

      await tester.pump(const Duration(milliseconds: 500)); // ad up, guard off
      expect(ads.interstitialOnScreen, isTrue);
      expect(c.progress.interstitialsShown, 1);
      expectAllDisabled(tester);
      final over = gameOf(tester).session;
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('PLAY AGAIN'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GameScreen), findsOneWidget);
      expect(identical(gameOf(tester).session, over), isTrue);
      expect(gameOf(tester).phase.value, RunPhase.over);

      await tester.pump(const Duration(seconds: 5)); // ad closes
      expect(ads.interstitialOnScreen, isFalse);
      expect(find.text('PLAY AGAIN'), findsOneWidget); // on Results
      expectAllEnabled(tester);

      final tap = tester.binding.clock.now();
      await tapPlayAgain(tester);
      expect(gameOf(tester).phase.value, RunPhase.ready);
      expect(tester.binding.clock.now().difference(tap),
          lessThan(const Duration(seconds: 1)));
      expect(ads.interstitialShowCalls, 1);
    });

    testWidgets('back inside the ad (SDK dismiss): player is on Results, '
        'not Home', (tester) async {
      final (c, ads) = rig(adUp: null);
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(ads.interstitialOnScreen, isTrue);
      ads.dismissInterstitial(); // the SDK consumed back and closed the ad
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400)); // entry guard
      expectAllEnabled(tester);
    });

    testWidgets('ad never appears: locked at 1.9 s, usable at 2 s, back '
        'then goes Home', (tester) async {
      final (c, ads) = rig(appearsAfter: null);
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(milliseconds: 1900));
      expectAllDisabled(tester);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(GameScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100)); // 2.0 s
      expectAllEnabled(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
      expect(ads.interstitialShowCalls, 1);
      expect(c.progress.interstitialsShown, 0);
    });

    testWidgets('ad fails to show: Results usable at once', (tester) async {
      final (c, ads) = rig();
      ads.interstitialScript = const InterstitialScript(
          appearsAfter: Duration(milliseconds: 100), fails: true);
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(milliseconds: 400)); // guard off
      expectAllEnabled(tester);
      expect(c.progress.interstitialsShown, 0);
    });

    testWidgets('back during the lock is ignored (route not popped)',
        (tester) async {
      final (c, _) = rig(adUp: const Duration(seconds: 3));
      await pushGame(tester, c);
      await endRun(tester);
      for (var i = 0; i < 3; i++) {
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(c.progress.runs, 6); // the run was applied once
      await tester.pump(const Duration(seconds: 3)); // ad closes
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
    });

    testWidgets('non-eligible run 4: usable right after the 400 ms entry '
        'guard', (tester) async {
      final (c, ads) = rig(nextRun: 4);
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expectAllEnabled(tester);
      expect(ads.interstitialShowCalls, 0);
      await tapPlayAgain(tester);
      expect(gameOf(tester).phase.value, RunPhase.ready);
    });
  });

  group('GAME-4 / AD-5 leaving Results never shows an ad', () {
    testWidgets('Play again never shows an ad (runs 6, 9, 12 chained)',
        (tester) async {
      final (c, ads) = rig();
      await pushGame(tester, c);
      for (final run in [6, 7, 8, 9, 10, 11, 12]) {
        now = now.add(const Duration(minutes: 2)); // 90 s gap always met
        ads.loadedInterstitialAge = const Duration(minutes: 1);
        final before = ads.interstitialShowCalls;
        gameOf(tester).tapInput();
        await endRun(tester);
        expect(c.progress.runs, run);
        final eligible = run % 3 == 0;
        expect(ads.interstitialShowCalls, before + (eligible ? 1 : 0),
            reason: 'run $run at Results-open');
        await tester.pump(const Duration(seconds: 6)); // ad closes
        final atTap = ads.interstitialShowCalls;
        await tapPlayAgain(tester);
        expect(gameOf(tester).phase.value, RunPhase.ready);
        await tester.pump(const Duration(seconds: 3));
        expect(ads.interstitialShowCalls, atTap, reason: 'run $run Play again');
      }
      expect(ads.interstitialShowCalls, 3);
      expect(c.progress.interstitialsShown, 3);
    });

    testWidgets('Play again never shows an ad, even when the rules would now '
        'allow one (old leave-Results bug A1)', (tester) async {
      // Run 6 opens inside the 90 s gap (not eligible); by the time the
      // player taps Play again the gap is met and an ad is loaded.
      final (c, ads) =
          rig(lastShownAt: now.subtract(const Duration(seconds: 30)));
      await pushGame(tester, c);
      await endRun(tester);
      expect(c.lastInterstitialDecision, InterstitialDecision.notEligible);
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(milliseconds: 400));
      await tapPlayAgain(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(gameOf(tester).phase.value, RunPhase.ready);
      expect(ads.interstitialShowCalls, 0);
    });

    testWidgets('Home never shows an ad (eligible run 9, after the lock; and '
        'the A1 case)', (tester) async {
      final (c, ads) = rig(nextRun: 9);
      await pushGame(tester, c);
      await endRun(tester);
      expect(ads.interstitialShowCalls, 1);
      await tester.pump(const Duration(seconds: 6));
      ads.loadedInterstitialAge = const Duration(minutes: 1);
      now = now.add(const Duration(minutes: 5));
      await tester.tap(find.text('Home'));
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
      expect(ads.interstitialShowCalls, 1);

      // Back from Results (after the lock) never shows one either.
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 16));
      gameOf(tester).tapInput();
      await endRun(tester); // run 10: not eligible
      await tester.pump(const Duration(milliseconds: 400));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
      expect(ads.interstitialShowCalls, 1);
    });
  });

  group('AD-6 / AD-7 / AD-5 (a) on the Results screen', () {
    testWidgets('revive ad watched on run 6: no interstitial, Results usable',
        (tester) async {
      final (c, ads) = rig(rewardedWatched: true);
      await pushGame(tester, c);
      await crashNow(tester);
      await waitForOverlay(tester);
      await tester.tap(find.text('Watch ad to revive'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(gameOf(tester).phase.value, RunPhase.playing);
      gameOf(tester).session!.invincibleSeconds = 0;
      await crashNow(tester);
      await waitForOverlay(tester);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(c.lastInterstitialDecision, InterstitialDecision.skippedRewarded);
      expect(ads.interstitialShowCalls, 0);
      expect(button(tester, 'PLAY AGAIN').enabled, isTrue);
    });

    testWidgets('revive ad closed early on run 6: no interstitial',
        (tester) async {
      final (c, ads) = rig(rewardedWatched: false); // closes early
      await pushGame(tester, c);
      await crashNow(tester);
      await waitForOverlay(tester);
      await tester.tap(find.text('Watch ad to revive'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(c.lastInterstitialDecision, InterstitialDecision.skippedRewarded);
      expect(ads.interstitialShowCalls, 0);
    });

    testWidgets('revive ad failed to show on run 6: interstitial rules apply',
        (tester) async {
      final (c, ads) = rig();
      ads.rewardedOutcome = RewardedOutcome.failedToShow;
      await pushGame(tester, c);
      await crashNow(tester);
      await waitForOverlay(tester);
      await tester.tap(find.text('Watch ad to revive'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(c.lastInterstitialDecision, InterstitialDecision.show);
      expect(ads.interstitialShowCalls, 1);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('not loaded on run 6: usable at once, no spinner or message, '
        'a later load is not shown on Results or in play', (tester) async {
      final (c, ads) = rig();
      ads.loadedInterstitialAge = null;
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expectAllEnabled(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(ads.interstitialLoadRequests, 1);
      ads.finishInterstitialLoad();
      await tester.pump(const Duration(seconds: 2));
      await tapPlayAgain(tester);
      gameOf(tester).tapInput();
      await tester.pump(const Duration(milliseconds: 500));
      expect(ads.interstitialShowCalls, 0);
      expect(c.progress.interstitialsShown, 0);
    });

    testWidgets('remove_ads on run 6 with an ad loaded: never shown',
        (tester) async {
      final (c, ads) = rig(removeAds: true);
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expectAllEnabled(tester);
      expect(ads.interstitialShowCalls, 0);
    });
  });

  group('S2 late ad: never over a moving run', () {
    testWidgets('ad appears after the lock and after Play again + start: the '
        'run freezes under it, resumes after; counted once', (tester) async {
      final (c, ads) = rig(appearsAfter: null, adUp: null);
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(seconds: 2)); // lock lifts
      expectAllEnabled(tester);
      await tapPlayAgain(tester);
      gameOf(tester).tapInput(); // start flying
      await tester.pump(const Duration(milliseconds: 100));
      final g = gameOf(tester);
      expect(g.phase.value, RunPhase.playing);
      g.session!.invincibleSeconds = 1e9; // keep the run alive for the test

      ads.appearInterstitial(); // the SDK shows it late anyway
      await tester.pump();
      expect(g.paused, isTrue);
      expect(c.progress.interstitialsShown, 1); // counts (AD-9)
      expect(c.lateInterstitials, 1);
      final frozenAt = g.session!.distanceMeters;
      await tester.tapAt(const Offset(200, 300));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(g.session!.distanceMeters, frozenAt);
      expect(g.phase.value, RunPhase.playing);

      ads.dismissInterstitial();
      await tester.pump();
      expect(g.paused, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.session!.distanceMeters, greaterThan(frozenAt));
      expect(ads.interstitialShowCalls, 1);
      expect(find.text('PLAY AGAIN'), findsNothing); // no screen change
    });

    testWidgets('ad appears late after Home: counted, nothing breaks',
        (tester) async {
      final (c, ads) = rig(appearsAfter: null, adUp: null);
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Home'));
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
      ads.appearInterstitial();
      ads.dismissInterstitial();
      await tester.pump();
      expect(c.progress.interstitialsShown, 1);
      expect(c.lateInterstitials, 1);
      expect(c.interstitialOnScreen.value, isFalse);
      expect(ads.interstitialShowCalls, 1);
    });

    testWidgets('ad appears late while still on Results: no re-lock',
        (tester) async {
      final (c, ads) = rig(appearsAfter: null, adUp: null);
      await pushGame(tester, c);
      await endRun(tester);
      await tester.pump(const Duration(seconds: 3));
      ads.appearInterstitial();
      await tester.pump();
      ads.dismissInterstitial();
      await tester.pump();
      expectAllEnabled(tester);
      expect(c.progress.interstitialsShown, 1);
    });
  });

  testWidgets('app kill during the ad: run, crystals and the ad are on disk',
      (tester) async {
    final store = InstantStore();
    final ads = FakeAds(ready: true)
      ..loadedInterstitialAge = const Duration(minutes: 1)
      ..interstitialScript = const InterstitialScript(dismissAfter: null);
    final c = makeController(runs: 5, ads: ads, store: store, clock: () => now);
    await pushGame(tester, c);
    await endRun(tester, crystals: 8);
    await tester.pump(const Duration(milliseconds: 300));
    expect(ads.interstitialOnScreen, isTrue);
    final disk = store.onDisk; // what a restart would load
    expect(disk.runs, 6);
    expect(disk.crystals, 8);
    expect(disk.interstitialsShown, 1);
    expect(disk.lastInterstitialAt, now);
    ads.dismissInterstitial();
  });
}
