/// Interstitial rules from spec v2 §3.2 / §3.3 (AD-5 to AD-9). Pure Dart so
/// `flutter test` covers every branch.
library;

/// What the game does with the interstitial when the Results screen opens.
enum InterstitialDecision {
  /// AD-5 (a)–(c) not all met: the run was never eligible. No ad, no lock.
  notEligible,

  /// AD-6: a rewarded ad was shown during this run. Skipped, not deferred.
  skippedRewarded,

  /// AD-7: no ad loaded, still loading, or older than [InterstitialRule.maxAdAge].
  /// Skipped silently; a new load is requested.
  notLoaded,

  /// All of AD-5 (a)–(e) hold: show the loaded ad now, over Results.
  show,
}

class InterstitialRule {
  InterstitialRule._();

  /// AD-5 (b): lifetime runs 6, 9, 12, ...
  static const int everyNthRun = 3;

  /// AD-5 (b): no interstitial in the first 3 runs of a player's life.
  static const int graceRuns = 3;

  /// AD-5 (c): at least 90 s between interstitials.
  static const Duration minGap = Duration(seconds: 90);

  /// AD-7: an interstitial older than this is treated as not loaded.
  static const Duration maxAdAge = Duration(hours: 1);

  /// AD-8 / OD-4: the Results lock lifts this long after Results-open if
  /// the ad hasn't appeared.
  static const Duration showDeadline = Duration(seconds: 2);

  /// The AD-5 decision, checked in spec §3.3 order.
  ///
  /// - [runs] is `stats.runs` after counting the run that just ended.
  /// - [lastShownAt] later than [now] (clock moved back) counts as absent
  ///   (AD-9).
  /// - [rewardedShownThisRun]: a revive ad was shown this run, watched to
  ///   the end or closed early (AD-6). A token revive is not a rewarded ad.
  /// - [loadedAdAge] is null when no ad is loaded. It comes from a monotonic
  ///   stopwatch, so a clock change can't make an old ad look fresh.
  static InterstitialDecision decide({
    required bool removeAds,
    required int runs,
    required DateTime now,
    required DateTime? lastShownAt,
    required bool rewardedShownThisRun,
    required Duration? loadedAdAge,
  }) {
    if (removeAds) return InterstitialDecision.notEligible; // (a)
    if (runs <= graceRuns || runs % everyNthRun != 0) {
      return InterstitialDecision.notEligible; // (b)
    }
    if (!gapMet(now: now, lastShownAt: lastShownAt)) {
      return InterstitialDecision.notEligible; // (c)
    }
    if (rewardedShownThisRun) return InterstitialDecision.skippedRewarded; // (d)
    if (loadedAdAge == null || loadedAdAge >= maxAdAge) {
      return InterstitialDecision.notLoaded; // (e)
    }
    return InterstitialDecision.show;
  }

  /// AD-5 (c) with the AD-9 clock rule: no previous ad, a previous ad in the
  /// future, or one at least [minGap] ago.
  static bool gapMet({required DateTime now, required DateTime? lastShownAt}) {
    if (lastShownAt == null || lastShownAt.isAfter(now)) return true;
    return now.difference(lastShownAt) >= minGap;
  }
}
