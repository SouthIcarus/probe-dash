import 'package:flutter/foundation.dart';

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

  /// Records a finished run and saves. Returns true on a new best.
  Future<bool> completeRun(RunResult result) async {
    final newBest = progress.applyRun(result);
    notifyListeners();
    await store.save(progress);
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

  Future<bool> buyUpgrade(UpgradeType type) async {
    if (!progress.buyUpgrade(type)) return false;
    notifyListeners();
    await store.save(progress);
    return true;
  }

  /// Called when leaving the results screen; shows an interstitial only
  /// when the spec's ad rules allow it (AD-1).
  Future<void> maybeShowInterstitial() async {
    final now = DateTime.now().toUtc();
    if (!AdPolicy.shouldShowInterstitial(
      runs: progress.runs,
      removeAds: progress.removeAds,
      now: now,
      lastShownAt: progress.lastInterstitialAt,
    )) {
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
