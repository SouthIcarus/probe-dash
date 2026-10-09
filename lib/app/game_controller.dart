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
  });

  final Progress progress;
  final SaveStore store;
  final AdService ads;

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
    final watched = await ads.showRewarded();
    if (!watched) return false;
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
    if (await ads.showInterstitial()) {
      progress
        ..lastInterstitialAt = now
        ..interstitialsShown += 1;
      await store.save(progress);
    }
  }
}
