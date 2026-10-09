import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/logic/upgrades.dart';

void main() {
  group('A-18 cheapest affordable upgrade', () {
    const none = <UpgradeType, int>{};

    test('shortcut label is short: "Upgrade: <name> Lv<n> – <cost> ◆"', () {
      final o = Upgrades.cheapestAffordable(none, 1000)!;
      expect(o.label, 'Upgrade: Crystal Value Lv1 – 100 ◆');
      // Longest possible label (longest name, Lv10, 4-digit cost) stays
      // within 36 characters, so it fits one line at 360 dp.
      final longest = UpgradeOffer(
          Upgrades.all.reduce((a, b) => a.name.length >= b.name.length ? a : b),
          Upgrades.maxLevel,
          9999);
      expect(longest.label.length, lessThanOrEqualTo(36));
    });

    test('nothing affordable: null', () {
      expect(Upgrades.cheapestAffordable(none, 99), isNull);
    });

    test('picks the cheapest affordable next level', () {
      final o = Upgrades.cheapestAffordable(none, 1000)!;
      expect(o.info.type, UpgradeType.crystalValue);
      expect(o.nextLevel, 1);
      expect(o.cost, 100);

      // Crystal Value Lv3 costs 225: Magnet Lv1 (150) is now cheapest.
      final m = Upgrades.cheapestAffordable(
          {UpgradeType.crystalValue: 2}, 1000)!;
      expect(m.info.type, UpgradeType.magnet);
      expect(m.cost, 150);
    });

    test('ties go to spec table order', () {
      // Crystal Value Lv2 and Magnet Lv1 both cost 150.
      final o = Upgrades.cheapestAffordable(
          {UpgradeType.crystalValue: 1}, 150)!;
      expect(o.info.type, UpgradeType.crystalValue);
      expect(o.nextLevel, 2);
    });

    test('maxed upgrades are skipped', () {
      final o = Upgrades.cheapestAffordable(
          {UpgradeType.crystalValue: Upgrades.maxLevel}, 1000)!;
      expect(o.info.type, UpgradeType.magnet);
    });
  });
}
