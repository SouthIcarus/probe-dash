import 'run_session.dart';
import 'upgrades.dart';

/// Everything saved between sessions (spec §6). Unknown or missing fields
/// fall back to defaults so old saves always load.
class Progress {
  Progress({
    this.crystals = 0,
    this.bestDistance = 0,
    Map<UpgradeType, int>? upgrades,
    this.runs = 0,
    this.interstitialsShown = 0,
    this.lastInterstitialAt,
    DateTime? firstOpenAt,
    this.removeAds = false,
  })  : upgrades = upgrades ?? {for (final t in UpgradeType.values) t: 0},
        firstOpenAt = firstOpenAt ?? DateTime.now().toUtc();

  static const int saveVersion = 1;

  int crystals;
  int bestDistance;
  final Map<UpgradeType, int> upgrades;
  int runs;
  int interstitialsShown;
  DateTime? lastInterstitialAt;
  final DateTime firstOpenAt;
  bool removeAds;

  int level(UpgradeType t) => upgrades[t] ?? 0;

  /// Applies a finished run. Returns true if it set a new best.
  bool applyRun(RunResult result) {
    runs++;
    crystals += result.earnedCrystals;
    if (result.distanceMeters > bestDistance) {
      bestDistance = result.distanceMeters;
      return true;
    }
    return false;
  }

  /// Rewarded "2× crystals" on the results screen: adds the run's earnings
  /// once more. The caller makes sure it's offered once per run.
  void applyDoubleCrystals(RunResult result) {
    crystals += result.earnedCrystals;
  }

  /// Spec US-3: level up and pay together, or do nothing.
  bool buyUpgrade(UpgradeType t) {
    final cost = Upgrades.nextCost(t, level(t));
    if (cost == null || crystals < cost) return false;
    crystals -= cost;
    upgrades[t] = level(t) + 1;
    return true;
  }

  Map<String, Object?> toJson() => {
        'saveVersion': saveVersion,
        'crystals': crystals,
        'bestDistance': bestDistance,
        'upgrades': {for (final e in upgrades.entries) e.key.name: e.value},
        'entitlements': {'removeAds': removeAds},
        'stats': {
          'runs': runs,
          'firstOpenAt': firstOpenAt.toIso8601String(),
          'lastInterstitialAt': lastInterstitialAt?.toIso8601String(),
          'interstitialsShown': interstitialsShown,
        },
      };

  factory Progress.fromJson(Map<String, Object?> json) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    DateTime? asDate(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toUtc() : null;

    final up = json['upgrades'];
    final ent = json['entitlements'];
    final stats = json['stats'];
    final statsMap = stats is Map ? stats : const {};

    return Progress(
      crystals: asInt(json['crystals']),
      bestDistance: asInt(json['bestDistance']),
      upgrades: {
        for (final t in UpgradeType.values)
          t: (up is Map ? asInt(up[t.name]) : 0).clamp(0, Upgrades.maxLevel),
      },
      removeAds: ent is Map && ent['removeAds'] == true,
      runs: asInt(statsMap['runs']),
      interstitialsShown: asInt(statsMap['interstitialsShown']),
      lastInterstitialAt: asDate(statsMap['lastInterstitialAt']),
      firstOpenAt: asDate(statsMap['firstOpenAt']),
    );
  }
}

/// Interstitial rules from spec §3.2: every 3rd run, never in the first 3
/// runs, at least 90 seconds apart, never with Remove Ads.
class AdPolicy {
  AdPolicy._();

  static const int everyNthRun = 3;
  static const int graceRuns = 3;
  static const Duration minGap = Duration(seconds: 90);

  /// [runs] is the number of completed runs, including the one just ended.
  static bool shouldShowInterstitial({
    required int runs,
    required bool removeAds,
    required DateTime now,
    DateTime? lastShownAt,
  }) {
    if (removeAds) return false;
    if (runs <= graceRuns) return false;
    if (runs % everyNthRun != 0) return false;
    if (lastShownAt != null && now.difference(lastShownAt) < minGap) {
      return false;
    }
    return true;
  }
}
