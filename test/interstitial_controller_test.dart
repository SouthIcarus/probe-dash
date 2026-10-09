// Spec v2 US-5 / AD-5 to AD-9 through GameController.openResults (plan step
// A-3). `testWidgets` only for its fake clock: timers advance with
// `tester.pump(duration)`; no widget is built.
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/app/game_controller.dart';
import 'package:probe_dash/logic/ad_rules.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/services/ad_service.dart';

import 'support/fakes.dart';

RunResult runResult({int crystals = 5, bool revived = false}) => RunResult(
      distanceMeters: 100,
      rawCrystals: crystals,
      earnedCrystals: crystals,
      nearMisses: 0,
      revived: revived,
    );

/// A controller one run before [nextRun], with a fresh interstitial loaded.
class Rig {
  Rig({
    int nextRun = 6,
    bool removeAds = false,
    DateTime? lastShownAt,
    Duration? adAge = const Duration(minutes: 1),
    InterstitialScript script = const InterstitialScript(),
  }) {
    ads = FakeAds(ready: true)
      ..log = log
      ..loadedInterstitialAge = adAge
      ..interstitialScript = script;
    store = InstantStore(log: log);
    c = makeController(
      runs: nextRun - 1,
      removeAds: removeAds,
      lastInterstitialAt: lastShownAt,
      ads: ads,
      store: store,
      clock: () => now,
    );
  }

  final log = <String>[];
  DateTime now = DateTime.utc(2026, 10, 9, 12);
  late final FakeAds ads;
  late final InstantStore store;
  late final GameController c;

  bool unlocked = false;
  int unlockCount = 0;

  ResultsOpen open({int crystals = 5, bool revived = false}) {
    c.runStarted();
    return openNow(crystals: crystals, revived: revived);
  }

  /// Results-open without resetting the per-run flag (after a revive ad).
  ResultsOpen openNow({int crystals = 5, bool revived = false}) {
    unlocked = false;
    final r = c.openResults(runResult(crystals: crystals, revived: revived));
    r.unlocked.then((_) {
      unlocked = true;
      unlockCount++;
    });
    return r;
  }
}

void main() {
  const ms = Duration(milliseconds: 1);

  group('US-5 happy path (AD-5, AD-8, AD-9)', () {
    testWidgets('run 6: saved, then shown; counted on appear; unlocked on '
        'dismiss', (tester) async {
      final r = Rig();
      final res = r.open(crystals: 7);
      expect(res.decision, InterstitialDecision.show);
      expect(res.locked, isTrue);
      await tester.pump(Duration.zero);
      // AD-5: run saved before the show was requested.
      expect(r.log, ['save', 'show']);
      expect(r.store.saved.first['stats'], containsPair('runs', 6));
      expect(r.store.saved.first['crystals'], 7);
      expect(r.c.progress.interstitialsShown, 0);

      await tester.pump(const Duration(milliseconds: 300)); // ad appears
      expect(r.log, ['save', 'show', 'appear', 'save']);
      expect(r.c.progress.interstitialsShown, 1);
      expect(r.c.progress.lastInterstitialAt, r.now);
      expect(r.c.interstitialOnScreen.value, isTrue);
      expect(r.unlocked, isFalse);

      // The lock holds while the ad is up, even past 2 s (AD-8).
      await tester.pump(const Duration(seconds: 5));
      expect(r.unlocked, isFalse);

      r.ads.dismissInterstitial();
      await tester.pump(Duration.zero);
      expect(r.unlocked, isTrue);
      expect(r.unlockCount, 1);
      expect(r.c.interstitialOnScreen.value, isFalse);
      expect(r.c.lateInterstitials, 0);
      expect(r.ads.interstitialShowCalls, 1);
    });

    testWidgets('app killed during the ad: count already on disk (AD-9)',
        (tester) async {
      final r = Rig();
      r.open(crystals: 9);
      await tester.pump(const Duration(milliseconds: 300)); // on screen
      expect(r.ads.interstitialOnScreen, isTrue);
      // "Kill": read back what was last saved, before any dismiss.
      final reopened = r.store.onDisk;
      expect(reopened.interstitialsShown, 1);
      expect(reopened.lastInterstitialAt, r.now);
      expect(reopened.runs, 6);
      expect(reopened.crystals, 9);
      r.ads.dismissInterstitial();
    });
  });

  group('AD-8 lock ends on failure or timeout', () {
    testWidgets('show_failed: unlocks at once, nothing counted, load '
        'requested', (tester) async {
      final r = Rig(
          script: const InterstitialScript(
              appearsAfter: Duration(milliseconds: 300), fails: true));
      r.open();
      await tester.pump(const Duration(milliseconds: 299));
      expect(r.unlocked, isFalse);
      await tester.pump(ms);
      expect(r.unlocked, isTrue);
      expect(r.c.progress.interstitialsShown, 0);
      expect(r.c.progress.lastInterstitialAt, isNull);
      expect(r.ads.interstitialLoadRequests, 1);
      expect(r.c.interstitialOnScreen.value, isFalse);
    });

    testWidgets('show_timeout: locked at 1.9 s, unlocked at 2.0 s, nothing '
        'counted', (tester) async {
      final r = Rig(script: const InterstitialScript(appearsAfter: null));
      r.open();
      await tester.pump(const Duration(milliseconds: 1900));
      expect(r.unlocked, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(r.unlocked, isTrue);
      expect(r.c.progress.interstitialsShown, 0);
      expect(r.ads.interstitialShowCalls, 1);
    });

    testWidgets('late ad (S2): appears at 3 s, counted and saved, unlock '
        'only once, never requested again', (tester) async {
      final r = Rig(script: const InterstitialScript(appearsAfter: null));
      r.open();
      await tester.pump(const Duration(seconds: 2));
      expect(r.unlocked, isTrue);

      await tester.pump(const Duration(seconds: 1));
      r.now = r.now.add(const Duration(seconds: 3));
      r.ads.appearInterstitial(); // the SDK shows it anyway
      expect(r.c.progress.interstitialsShown, 1);
      expect(r.c.progress.lastInterstitialAt, r.now);
      expect(r.store.onDisk.interstitialsShown, 1);
      expect(r.c.lateInterstitials, 1);
      expect(r.c.interstitialOnScreen.value, isTrue); // screen freezes game

      r.ads.dismissInterstitial();
      await tester.pump(Duration.zero);
      expect(r.unlockCount, 1);
      expect(r.c.interstitialOnScreen.value, isFalse);
      expect(r.ads.interstitialShowCalls, 1);
    });

    testWidgets('save still running at 2 s: the ad is not requested at all',
        (tester) async {
      final ads = FakeAds()..loadedInterstitialAge = const Duration(minutes: 1);
      final store = SlowStore();
      final c = makeController(runs: 5, ads: ads, store: store);
      var unlocked = false;
      c.openResults(runResult()).unlocked.then((_) => unlocked = true);
      await tester.pump(const Duration(seconds: 2));
      expect(unlocked, isTrue);
      store.pending.first.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(ads.interstitialShowCalls, 0); // never a late request
      expect(c.progress.runs, 6);
    });

    testWidgets('slow save that finishes in time: shown after the save',
        (tester) async {
      final ads = FakeAds()..loadedInterstitialAge = const Duration(minutes: 1);
      final store = SlowStore();
      final c = makeController(runs: 5, ads: ads, store: store);
      c.openResults(runResult());
      await tester.pump(const Duration(milliseconds: 500));
      expect(ads.interstitialShowCalls, 0);
      store.pending.first.complete();
      await tester.pump(Duration.zero);
      expect(ads.interstitialShowCalls, 1);
      await tester.pump(const Duration(milliseconds: 300)); // appears
      store.pending.last.complete();
      ads.dismissInterstitial();
      await tester.pump(Duration.zero);
    });
  });

  group('AD-7 not loaded / expired', () {
    testWidgets('none loaded: usable at once, nothing counted, a load is '
        'requested, and a later load is never shown', (tester) async {
      final r = Rig(adAge: null);
      final res = r.open();
      expect(res.decision, InterstitialDecision.notLoaded);
      expect(res.locked, isFalse);
      await tester.pump(Duration.zero);
      expect(r.unlocked, isTrue);
      expect(r.ads.interstitialLoadRequests, 1);
      expect(r.c.progress.interstitialsShown, 0);

      r.ads.finishInterstitialLoad(); // load finishes while on Results
      await tester.pump(const Duration(seconds: 10));
      expect(r.ads.interstitialShowCalls, 0);
    });

    testWidgets('expired (61 min): discarded, reloaded, not shown',
        (tester) async {
      final r = Rig(adAge: const Duration(minutes: 61));
      final res = r.open();
      expect(res.decision, InterstitialDecision.notLoaded);
      await tester.pump(Duration.zero);
      expect(r.unlocked, isTrue);
      expect(r.ads.staleInterstitialsDiscarded, 1);
      expect(r.ads.interstitialLoadRequests, 1);
      expect(r.ads.interstitialShowCalls, 0);
      expect(r.c.progress.interstitialsShown, 0);
    });

    testWidgets('59 min old: shown', (tester) async {
      final r = Rig(adAge: const Duration(minutes: 59));
      expect(r.open().decision, InterstitialDecision.show);
      await tester.pump(const Duration(milliseconds: 300));
      expect(r.c.progress.interstitialsShown, 1);
      r.ads.dismissInterstitial();
    });
  });

  group('AD-6 revive ad vs token', () {
    Future<InterstitialDecision> afterRevive(
        WidgetTester tester, RewardedOutcome outcome) async {
      final r = Rig();
      r.c.runStarted();
      r.ads.rewardedOutcome = outcome;
      await r.c.showReviveAd();
      final d = r.openNow(revived: outcome == RewardedOutcome.earned).decision;
      await tester.pump(const Duration(milliseconds: 300));
      if (r.ads.interstitialOnScreen) r.ads.dismissInterstitial();
      await tester.pump(const Duration(seconds: 2));
      return d;
    }

    testWidgets('revive ad watched: interstitial skipped', (tester) async {
      expect(await afterRevive(tester, RewardedOutcome.earned),
          InterstitialDecision.skippedRewarded);
    });

    testWidgets('revive ad closed early: also skipped', (tester) async {
      expect(await afterRevive(tester, RewardedOutcome.closedEarly),
          InterstitialDecision.skippedRewarded);
    });

    testWidgets('revive ad failed to show: rule applies as normal',
        (tester) async {
      expect(await afterRevive(tester, RewardedOutcome.failedToShow),
          InterstitialDecision.show);
    });

    testWidgets('revive with a token (no rewarded ad): not skipped',
        (tester) async {
      final r = Rig();
      final res = r.open(revived: true); // revived, no showReviveAd call
      expect(res.decision, InterstitialDecision.show);
      await tester.pump(const Duration(milliseconds: 300));
      r.ads.dismissInterstitial();
    });

    testWidgets('skipped at run 6: next chance is run 9, not 7',
        (tester) async {
      final r = Rig();
      r.c.runStarted();
      r.ads.rewardedOutcome = RewardedOutcome.earned;
      await r.c.showReviveAd();
      expect(r.openNow().decision, InterstitialDecision.skippedRewarded);
      expect(r.open().decision, InterstitialDecision.notEligible); // 7
      expect(r.open().decision, InterstitialDecision.notEligible); // 8
      expect(r.open().decision, InterstitialDecision.show); // 9
      expect(r.c.progress.runs, 9);
      await tester.pump(const Duration(milliseconds: 300));
      r.ads.dismissInterstitial();
      expect(r.ads.interstitialShowCalls, 1);
    });

    testWidgets('the revive flag lasts one run only', (tester) async {
      final r = Rig();
      r.c.runStarted();
      r.ads.rewardedOutcome = RewardedOutcome.closedEarly;
      await r.c.showReviveAd();
      expect(r.c.rewardedShownThisRun, isTrue);
      r.c.runStarted();
      expect(r.c.rewardedShownThisRun, isFalse);
    });
  });

  group('AD-5 (a)–(c) through the controller', () {
    testWidgets('remove_ads with a loaded ad: never shown, runs 4–15',
        (tester) async {
      final r = Rig(nextRun: 4, removeAds: true);
      for (var i = 0; i < 12; i++) {
        r.now = r.now.add(const Duration(minutes: 5));
        expect(r.open().decision, InterstitialDecision.notEligible);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(r.ads.interstitialShowCalls, 0);
    });

    testWidgets('grace and cadence: 18 runs from a fresh install show at '
        '6, 9, 12, 15, 18 only', (tester) async {
      final r = Rig(nextRun: 1, script: const InterstitialScript(
          appearsAfter: Duration(milliseconds: 300),
          dismissAfter: Duration(seconds: 5)));
      final shownAt = <int>[];
      for (var run = 1; run <= 18; run++) {
        r.ads.loadedInterstitialAge = const Duration(minutes: 1);
        r.now = r.now.add(const Duration(minutes: 2)); // gap always met
        if (r.open().decision == InterstitialDecision.show) shownAt.add(run);
        await tester.pump(const Duration(seconds: 6));
      }
      expect(shownAt, [6, 9, 12, 15, 18]);
      expect(r.c.progress.interstitialsShown, 5);
    });

    testWidgets('90 s gap: shown at 6; run 9 60 s later skipped; run 12 '
        '90 s after the ad shown', (tester) async {
      final r = Rig(
          script: const InterstitialScript(
              appearsAfter: Duration(milliseconds: 300),
              dismissAfter: Duration(seconds: 5)));
      expect(r.open().decision, InterstitialDecision.show);
      await tester.pump(const Duration(seconds: 6));
      final shownAt = r.c.progress.lastInterstitialAt!;
      r.open(); // 7
      r.open(); // 8
      r.now = shownAt.add(const Duration(seconds: 60));
      r.ads.loadedInterstitialAge = const Duration(minutes: 1);
      expect(r.open().decision, InterstitialDecision.notEligible); // 9
      r.open(); // 10
      r.open(); // 11
      r.now = shownAt.add(const Duration(seconds: 90));
      expect(r.open().decision, InterstitialDecision.show); // 12
      await tester.pump(const Duration(seconds: 6));
      expect(r.c.progress.interstitialsShown, 2);
    });

    testWidgets('clock moved back: lastInterstitialAt in the future counts '
        'as absent', (tester) async {
      final now = DateTime.utc(2026, 10, 9, 12);
      final r = Rig(lastShownAt: now.add(const Duration(hours: 1)));
      expect(r.open().decision, InterstitialDecision.show);
      await tester.pump(const Duration(milliseconds: 300));
      expect(r.c.progress.lastInterstitialAt, now); // replaced by real time
      r.ads.dismissInterstitial();
    });
  });

  group('rewarded 2× still pays only when watched (US-1)', () {
    testWidgets('closed early: no reward; earned: reward', (tester) async {
      final ads = FakeAds(rewardedOutcome: RewardedOutcome.closedEarly);
      final c = makeController(ads: ads);
      final r = runResult(crystals: 10);
      c.openResults(r);
      expect(await c.doubleCrystals(r), isFalse);
      expect(c.progress.crystals, 10);
      ads.rewardedOutcome = RewardedOutcome.earned;
      expect(await c.doubleCrystals(r), isTrue);
      expect(c.progress.crystals, 20);
    });
  });
}
