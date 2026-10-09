import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/logic/progress.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/logic/upgrades.dart';

RunResult result({int distance = 500, int earned = 120}) => RunResult(
      distanceMeters: distance,
      rawCrystals: earned,
      earnedCrystals: earned,
      nearMisses: 0,
      revived: false,
    );

void main() {
  group('Upgrade costs', () {
    test('grow ×1.5 per level and stop at max', () {
      expect(Upgrades.nextCost(UpgradeType.shield, 0), 250);
      expect(Upgrades.nextCost(UpgradeType.shield, 1), 375);
      expect(Upgrades.nextCost(UpgradeType.shield, 2), 563);
      expect(Upgrades.nextCost(UpgradeType.shield, 10), isNull);
    });
  });

  group('US-3 buy upgrade', () {
    test('not enough crystals: nothing changes', () {
      final p = Progress(crystals: 99);
      expect(p.buyUpgrade(UpgradeType.crystalValue), isFalse);
      expect(p.crystals, 99);
      expect(p.level(UpgradeType.crystalValue), 0);
    });

    test('enough crystals: level up and pay together', () {
      final p = Progress(crystals: 300);
      expect(p.buyUpgrade(UpgradeType.crystalValue), isTrue);
      expect(p.crystals, 200);
      expect(p.level(UpgradeType.crystalValue), 1);
    });

    test('cannot go past max level', () {
      final p = Progress(
          crystals: 1 << 30, upgrades: {UpgradeType.magnet: Upgrades.maxLevel});
      expect(p.buyUpgrade(UpgradeType.magnet), isFalse);
      expect(p.crystals, 1 << 30);
    });
  });

  group('Runs', () {
    test('applyRun adds crystals, counts runs, tracks best', () {
      final p = Progress(bestDistance: 400);
      expect(p.applyRun(result(distance: 300)), isFalse);
      expect(p.applyRun(result(distance: 650)), isTrue);
      expect(p.bestDistance, 650);
      expect(p.runs, 2);
      expect(p.crystals, 240);
    });

    test('double crystals adds the run earnings once more', () {
      final p = Progress();
      final r = result(earned: 80);
      p.applyRun(r);
      p.applyDoubleCrystals(r);
      expect(p.crystals, 160);
    });
  });

  group('Save format (spec §6)', () {
    test('round-trips through JSON', () {
      final p = Progress(
        crystals: 1234,
        bestDistance: 987,
        upgrades: {
          UpgradeType.crystalValue: 2,
          UpgradeType.shield: 5,
          UpgradeType.magnet: 0,
          UpgradeType.headStart: 1,
        },
        runs: 17,
        interstitialsShown: 3,
        lastInterstitialAt: DateTime.utc(2026, 10, 7, 12),
        firstOpenAt: DateTime.utc(2026, 10, 1),
        removeAds: true,
      );
      final q = Progress.fromJson(p.toJson());
      expect(q.toJson(), p.toJson());
      expect(q.toJson()['saveVersion'], Progress.saveVersion);
    });

    test('empty or garbage saves load as defaults instead of crashing', () {
      final empty = Progress.fromJson({});
      expect(empty.crystals, 0);
      expect(empty.level(UpgradeType.shield), 0);

      final junk = Progress.fromJson({
        'crystals': 'lots',
        'upgrades': {'shield': 99, 'unknown': 3},
        'stats': 'nope',
        'entitlements': {'removeAds': 'yes'},
      });
      expect(junk.crystals, 0);
      expect(junk.level(UpgradeType.shield), Upgrades.maxLevel);
      expect(junk.removeAds, isFalse);
    });
  });
}
