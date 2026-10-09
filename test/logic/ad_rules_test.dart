import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/logic/ad_rules.dart';

/// Spec v2 §3.3 / AD-5 to AD-9: `InterstitialRule.decide`.
void main() {
  final now = DateTime.utc(2026, 10, 9, 12);
  const fresh = Duration(minutes: 5);

  InterstitialDecision decide(
    int runs, {
    bool removeAds = false,
    DateTime? last,
    bool rewarded = false,
    Duration? age = fresh,
  }) =>
      InterstitialRule.decide(
        removeAds: removeAds,
        runs: runs,
        now: now,
        lastShownAt: last,
        rewardedShownThisRun: rewarded,
        loadedAdAge: age,
      );

  const show = InterstitialDecision.show;
  const notEligible = InterstitialDecision.notEligible;

  group('AD-5 (b) grace runs and every-3rd-run cadence', () {
    test('runs 1, 2, 3: never (run 3 is inside the grace period)', () {
      expect([1, 2, 3].map(decide), everyElement(notEligible));
    });

    test('runs 4, 5, 7, 8, 10, 11: not a multiple of 3', () {
      expect([4, 5, 7, 8, 10, 11].map(decide), everyElement(notEligible));
    });

    test('runs 6, 9, 12, 300: show', () {
      expect([6, 9, 12, 300].map(decide), everyElement(show));
    });

    test('constants match the spec', () {
      expect(InterstitialRule.everyNthRun, 3);
      expect(InterstitialRule.graceRuns, 3);
      expect(InterstitialRule.minGap, const Duration(seconds: 90));
      expect(InterstitialRule.maxAdAge, const Duration(hours: 1));
      expect(InterstitialRule.showDeadline, const Duration(seconds: 2));
    });
  });

  group('AD-5 (c) 90 s gap', () {
    DateTime ago(int s) => now.subtract(Duration(seconds: s));

    test('none shown before: show', () {
      expect(decide(6, last: null), show);
    });

    test('60 s ago: not eligible', () {
      expect(decide(6, last: ago(60)), notEligible);
    });

    test('89 s ago: not eligible', () {
      expect(decide(6, last: ago(89)), notEligible);
    });

    test('exactly 90 s ago: show', () {
      expect(decide(6, last: ago(90)), show);
    });

    test('91 s ago: show', () {
      expect(decide(6, last: ago(91)), show);
    });
  });

  group('AD-9 clock moved back', () {
    test('lastShownAt 1 h in the future counts as absent: show', () {
      expect(decide(6, last: now.add(const Duration(hours: 1))), show);
    });

    test('lastShownAt 1 s in the future counts as absent: show', () {
      expect(decide(6, last: now.add(const Duration(seconds: 1))), show);
    });

    test('gapMet: future and null are met; recent is not', () {
      expect(InterstitialRule.gapMet(now: now, lastShownAt: null), isTrue);
      expect(
          InterstitialRule.gapMet(
              now: now, lastShownAt: now.add(const Duration(days: 3))),
          isTrue);
      expect(InterstitialRule.gapMet(now: now, lastShownAt: now), isFalse);
    });
  });

  group('AD-5 (a) remove_ads', () {
    test('owned, with a fresh ad loaded: never', () {
      expect(decide(6, removeAds: true), notEligible);
      expect(decide(9, removeAds: true), notEligible);
      expect(decide(12, removeAds: true), notEligible);
    });
  });

  group('AD-6 rewarded ad this run', () {
    test('revive ad shown: skippedRewarded, even with a fresh ad loaded', () {
      expect(decide(6, rewarded: true), InterstitialDecision.skippedRewarded);
    });

    test('token revive (no rewarded ad): rules apply as normal', () {
      expect(decide(6, rewarded: false), show);
    });

    test('skipped, not deferred: run 6 skipped, 7 and 8 not, 9 shows', () {
      expect(decide(6, rewarded: true), InterstitialDecision.skippedRewarded);
      expect(decide(7), notEligible);
      expect(decide(8), notEligible);
      expect(decide(9), show);
    });
  });

  group('AD-7 ad not loaded or expired', () {
    test('none loaded (null age): notLoaded', () {
      expect(decide(6, age: null), InterstitialDecision.notLoaded);
    });

    test('just loaded (age 0): show', () {
      expect(decide(6, age: Duration.zero), show);
    });

    test('59 min old: show', () {
      expect(decide(6, age: const Duration(minutes: 59)), show);
    });

    test('exactly 60 min old: notLoaded (expired)', () {
      expect(decide(6, age: const Duration(minutes: 60)),
          InterstitialDecision.notLoaded);
    });

    test('61 min old: notLoaded (expired)', () {
      expect(decide(6, age: const Duration(minutes: 61)),
          InterstitialDecision.notLoaded);
    });

    test('no deferral: run 6 notLoaded, run 7 notEligible, run 9 show', () {
      expect(decide(6, age: null), InterstitialDecision.notLoaded);
      expect(decide(7), notEligible);
      expect(decide(9), show);
    });
  });

  group('§3.3 check order', () {
    test('removeAds + rewarded: notEligible (no event for ineligible runs)',
        () {
      expect(decide(6, removeAds: true, rewarded: true), notEligible);
    });

    test('grace run + rewarded + not loaded: notEligible', () {
      expect(decide(3, rewarded: true, age: null), notEligible);
    });

    test('inside the 90 s gap + rewarded: notEligible', () {
      expect(
          decide(6,
              last: now.subtract(const Duration(seconds: 10)), rewarded: true),
          notEligible);
    });

    test('rewarded + not loaded: skippedRewarded (rewarded checked first)',
        () {
      expect(decide(6, rewarded: true, age: null),
          InterstitialDecision.skippedRewarded);
    });
  });
}
