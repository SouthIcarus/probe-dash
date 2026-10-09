import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/ad_rules.dart';
import '../logic/progress.dart';
import '../logic/run_session.dart';
import '../logic/upgrades.dart';
import '../services/ad_service.dart';
import '../services/save_store.dart';

/// App-wide state: the player's progress plus the save and ad services.
/// Screens listen to it and call its methods; it saves after every change
/// that matters (GAME-6).
class GameController extends ChangeNotifier {
  GameController({
    required this.progress,
    required this.store,
    required this.ads,
    DateTime Function()? clock,
  }) : clock = clock ?? _utcNow;

  final Progress progress;
  final SaveStore store;
  final AdService ads;

  /// Wall clock (UTC) for `stats.lastInterstitialAt` and the 90 s gap.
  /// Replaceable in tests (clock moved back, AD-9).
  final DateTime Function() clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  bool _rewardedShownThisRun = false;

  /// AD-6: a revive ad was shown during the current run (watched to the end
  /// or closed early). A token revive or an ad that failed to show doesn't
  /// count.
  bool get rewardedShownThisRun => _rewardedShownThisRun;

  final ValueNotifier<bool> _interstitialOnScreen = ValueNotifier(false);

  /// True from the moment an interstitial appears until it is dismissed or
  /// fails. The game screen freezes the game engine while it is true, so an
  /// ad that appears late (see [openResults]) never runs over a live run.
  ValueListenable<bool> get interstitialOnScreen => _interstitialOnScreen;

  /// Interstitials whose `onShown` arrived after the AD-8 lock had already
  /// lifted (the SDK can't cancel a requested show). Counted like any other
  /// shown ad (AD-9); kept for tests and the device check.
  int lateInterstitials = 0;

  /// A new run starts (first run on the screen, or "Play again"): clears the
  /// per-run AD-6 flag.
  void runStarted() => _rewardedShownThisRun = false;

  /// Rewarded revive ad (US-1, AD-6). Returns how it ended; only
  /// [RewardedOutcome.earned] revives. [RewardedOutcome.earned] and
  /// [RewardedOutcome.closedEarly] mark the run so its interstitial is
  /// skipped; [RewardedOutcome.failedToShow] and
  /// [RewardedOutcome.notLoaded] don't (nothing was shown).
  Future<RewardedOutcome> showReviveAd() async {
    final outcome = await ads.showRewarded();
    if (outcome == RewardedOutcome.earned ||
        outcome == RewardedOutcome.closedEarly) {
      _rewardedShownThisRun = true;
    }
    return outcome;
  }

  /// Results-open (spec v2 §7 `ResultsOpen`, §3.3). Call once per run.
  ///
  /// Applies the run (`stats.runs += 1`) and queues its save (GAME-6), then
  /// runs the AD-5 decision. If the decision is
  /// [InterstitialDecision.show], the ad is requested once the run save has
  /// finished (AD-5 "saved before the ad is shown") and
  /// [ResultsOpen.unlocked] completes when the ad is dismissed, fails to
  /// show, or [InterstitialRule.showDeadline] passes without it appearing
  /// (AD-8). Otherwise [ResultsOpen.unlocked] is already complete.
  ///
  /// This is the **only** place the game asks for an interstitial; leaving
  /// Results never does (GAME-4, AD-5).
  ///
  /// Late ads (decision S2): the SDK can't cancel a show once requested, so
  /// an ad may still appear after the 2 s lock lifted, possibly after the
  /// player tapped "Play again" or "Home". Handling, in order:
  /// 1. The show is requested only while the lock is still on: if the run
  ///    save takes the whole 2 s, the ad is not requested at all.
  /// 2. A late `onShown` is counted and saved like any shown ad (AD-9) and
  ///    added to [lateInterstitials]; it never re-locks Results or changes
  ///    the screen, and [ResultsOpen.unlocked] completes only once.
  /// 3. [interstitialOnScreen] turns true for as long as the ad is up; the
  ///    game screen freezes the engine (no physics, no crash, no score)
  ///    until it closes, so the ad can never cover a run that is moving.
  ResultsOpen openResults(RunResult result) {
    final newBest = progress.applyRun(result);
    notifyListeners();
    final runSaved = store.save(progress);
    final rewarded = _rewardedShownThisRun;
    _rewardedShownThisRun = false; // a run's flag is used once
    final age = ads.interstitialAge;
    final decision = InterstitialRule.decide(
      removeAds: progress.removeAds,
      runs: progress.runs,
      now: clock(),
      lastShownAt: progress.lastInterstitialAt,
      rewardedShownThisRun: rewarded,
      loadedAdAge: age,
    );
    lastInterstitialDecision = decision;
    switch (decision) {
      case InterstitialDecision.notEligible:
      case InterstitialDecision.skippedRewarded:
        return ResultsOpen._(newBest, decision, Future<void>.value());
      case InterstitialDecision.notLoaded:
        // AD-7: skip silently and load one for a later run. A stale ad is
        // thrown away; a fresh load is never shown in this run cycle.
        if (age != null) {
          ads.discardStaleInterstitial();
        } else {
          ads.requestInterstitialLoad();
        }
        return ResultsOpen._(newBest, decision, Future<void>.value());
      case InterstitialDecision.show:
        return ResultsOpen._(newBest, decision, _showAtResultsOpen(runSaved));
    }
  }

  /// The decision made at the last Results-open (for tests and analytics).
  InterstitialDecision? lastInterstitialDecision;

  Future<void> _showAtResultsOpen(Future<void> runSaved) {
    final unlocked = Completer<void>();
    void unlock() {
      if (!unlocked.isCompleted) unlocked.complete();
    }

    var appeared = false;
    final deadline = Timer(InterstitialRule.showDeadline, () {
      if (!appeared) unlock(); // AD-8: ad not on screen within 2 s
    });

    final saved = runSaved.then((_) {}, onError: (Object _) {});
    Future.any([saved, unlocked.future]).then((_) {
      // The lock already lifted while the save was pending: requesting the
      // ad now could only produce a late ad, so don't.
      if (unlocked.isCompleted) return;
      final requested = ads.showInterstitial(
        onShown: () {
          appeared = true;
          deadline.cancel();
          if (unlocked.isCompleted) lateInterstitials++;
          _onInterstitialShown();
        },
        onFailed: () {
          deadline.cancel();
          _interstitialOnScreen.value = false;
          unlock();
        },
        onDismissed: () {
          deadline.cancel();
          _interstitialOnScreen.value = false;
          unlock();
        },
      );
      if (!requested) {
        // The ad went away between the decision and the show: same as
        // not loaded (AD-7).
        deadline.cancel();
        ads.requestInterstitialLoad();
        unlock();
      }
    });
    return unlocked.future;
  }

  /// AD-9: count and save the ad the moment it appears, so an app kill
  /// during the ad still counts toward the 90 s gap.
  void _onInterstitialShown() {
    _interstitialOnScreen.value = true;
    progress
      ..lastInterstitialAt = clock()
      ..interstitialsShown += 1;
    notifyListeners();
    unawaited(store.save(progress));
  }

  /// Records a finished run and queues a save (GAME-6). Returns true on a
  /// new best. Doesn't wait for the save, so results show at once; saves
  /// are queued in order by [SaveStore] and never overlap.
  bool completeRun(RunResult result) {
    final newBest = progress.applyRun(result);
    notifyListeners();
    unawaited(store.save(progress));
    return newBest;
  }

  /// Rewarded "2× crystals" on the results screen. Returns true if granted.
  Future<bool> doubleCrystals(RunResult result) async {
    if (await ads.showRewarded() != RewardedOutcome.earned) return false;
    progress.applyDoubleCrystals(result);
    notifyListeners();
    await store.save(progress);
    return true;
  }

  bool _buying = false;

  /// How long a buy waits for its save before later buys are allowed again.
  /// A save normally takes milliseconds; this only matters if one never
  /// finishes, which must not block every later buy.
  static const Duration buySaveWaitLimit = Duration(seconds: 2);

  /// Buys one level (US-3). The level and price change at once (before the
  /// save). A buy that arrives while the previous one is still saving (fast
  /// double tap) is ignored, so one tap = one level (A-22); the wait is
  /// capped at [buySaveWaitLimit].
  Future<bool> buyUpgrade(UpgradeType type) async {
    if (_buying) return false;
    _buying = true;
    try {
      if (!progress.buyUpgrade(type)) return false;
      notifyListeners();
      await _waitAtMost(store.save(progress), buySaveWaitLimit);
      return true;
    } finally {
      _buying = false;
    }
  }

  static Future<void> _waitAtMost(Future<void> future, Duration limit) {
    final done = Completer<void>();
    final timer = Timer(limit, () {
      if (!done.isCompleted) done.complete();
    });
    future.then((_) {}, onError: (Object _) {}).whenComplete(() {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  /// Called when leaving the results screen; shows an interstitial only
  /// when the spec's ad rules allow it (AD-1).
  Future<void> maybeShowInterstitial() async {
    final now = DateTime.now().toUtc();
    // Interim (removed with this method in plan step A-3): the old
    // leave-Results trigger, now through the pure rule. The ad service still
    // decides whether an ad is loaded here.
    if (InterstitialRule.decide(
          removeAds: progress.removeAds,
          runs: progress.runs,
          now: now,
          lastShownAt: progress.lastInterstitialAt,
          rewardedShownThisRun: false,
          loadedAdAge: Duration.zero,
        ) !=
        InterstitialDecision.show) {
      return;
    }
    final closed = Completer<void>();
    final requested = ads.showInterstitial(
      onShown: () {
        progress
          ..lastInterstitialAt = now
          ..interstitialsShown += 1;
        unawaited(store.save(progress));
      },
      onFailed: () {
        if (!closed.isCompleted) closed.complete();
      },
      onDismissed: () {
        if (!closed.isCompleted) closed.complete();
      },
    );
    if (requested) await closed.future;
  }
}

/// What [GameController.openResults] returns to the Results screen.
class ResultsOpen {
  const ResultsOpen._(this.newBest, this.decision, this.unlocked);

  /// The run set a new best.
  final bool newBest;

  /// The AD-5 decision for this run.
  final InterstitialDecision decision;

  /// Completes when the AD-8 lock lifts. Already complete unless
  /// [decision] is [InterstitialDecision.show].
  final Future<void> unlocked;

  /// Whether Results opens locked (AD-8). On non-eligible runs the lock
  /// lasts 0 s (spec v2 §8).
  bool get locked => decision == InterstitialDecision.show;
}
