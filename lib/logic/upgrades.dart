import 'dart:math' as math;

import 'tuning.dart';

/// The four upgrades in spec §4 ("Upgrades" table).
enum UpgradeType { crystalValue, shield, magnet, headStart }

class UpgradeInfo {
  const UpgradeInfo(this.type, this.name, this.baseCost, this.description);

  final UpgradeType type;
  final String name;
  final int baseCost;
  final String description;
}

/// One upgrade level the player could buy now.
class UpgradeOffer {
  const UpgradeOffer(this.info, this.nextLevel, this.cost);

  final UpgradeInfo info;
  final int nextLevel;
  final int cost;

  /// The results-screen shortcut label (A-18), short enough for one line
  /// on a 360 dp wide phone: "Upgrade: Crystal Value Lv1 – 100 ◆".
  String get label => 'Upgrade: ${info.name} Lv$nextLevel – $cost ◆';
}

class Upgrades {
  Upgrades._();

  static const int maxLevel = 10;
  static const double costGrowth = 1.5;

  static const List<UpgradeInfo> all = [
    UpgradeInfo(UpgradeType.crystalValue, 'Crystal Value', 100,
        '+10% crystals per level'),
    UpgradeInfo(UpgradeType.shield, 'Shield', 250,
        'Absorbs hits: 1 at Lv1, 2 at Lv5, 3 at Lv10. Longer recovery each level'),
    UpgradeInfo(UpgradeType.magnet, 'Magnet', 150,
        'Magnet pickups last 0.5s longer per level'),
    UpgradeInfo(UpgradeType.headStart, 'Head Start', 200,
        'Rocket past the first 50 m per level'),
  ];

  static UpgradeInfo info(UpgradeType type) =>
      all.firstWhere((u) => u.type == type);

  /// Cost to go from [currentLevel] to the next level, or null at max.
  static int? nextCost(UpgradeType type, int currentLevel) {
    if (currentLevel >= maxLevel) return null;
    return (info(type).baseCost * math.pow(costGrowth, currentLevel)).round();
  }

  /// The cheapest next level the player can afford with [crystals], or null
  /// if none is affordable (results "UpgradesShortcut", spec §8, A-18).
  /// Ties go to the order of the spec's upgrades table ([all]).
  static UpgradeOffer? cheapestAffordable(
      Map<UpgradeType, int> levels, int crystals) {
    UpgradeOffer? best;
    for (final u in all) {
      final level = levels[u.type] ?? 0;
      final cost = nextCost(u.type, level);
      if (cost == null || cost > crystals) continue;
      if (best == null || cost < best.cost) {
        best = UpgradeOffer(u, level + 1, cost);
      }
    }
    return best;
  }

  static double crystalMultiplier(int level) => 1 + 0.1 * level;

  /// Spec: 1 hit at Lv1, +1 at Lv5 and Lv10.
  static int shieldHits(int level) {
    if (level >= 10) return 3;
    if (level >= 5) return 2;
    if (level >= 1) return 1;
    return 0;
  }

  /// Invincibility after a shield absorbs a hit. Grows every level so no
  /// shield level is a dead purchase.
  static double shieldGraceSeconds(int level) =>
      Tuning.shieldGraceBaseSeconds + Tuning.shieldGracePerLevel * level;

  static double magnetSeconds(int level) =>
      Tuning.magnetBaseSeconds + 0.5 * level;

  static double headStartMeters(int level) =>
      Tuning.headStartMetersPerLevel * level;
}
