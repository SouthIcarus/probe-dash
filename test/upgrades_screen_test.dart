import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/logic/upgrades.dart';
import 'package:probe_dash/ui/upgrades_screen.dart';

import 'support/fakes.dart';

Finder buyButton(String name) => find.descendant(
    of: find.ancestor(
        of: find.textContaining(name), matching: find.byType(Card)),
    matching: find.byType(FilledButton));

void main() {
  group('A-22 one tap, one level', () {
    testWidgets('two taps 100 ms apart buy exactly one level',
        (tester) async {
      // 100 + 150 = 250: enough for two Crystal Value levels.
      final c = makeController(crystals: 250);
      await tester.pumpWidget(MaterialApp(home: UpgradesScreen(controller: c)));

      await tester.tap(buyButton('Crystal Value'));
      await tester.pump(const Duration(milliseconds: 100));
      // The tile now offers the next level for 150; a second tap lands on it.
      await tester.tap(buyButton('Crystal Value'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(c.progress.level(UpgradeType.crystalValue), 1);
      expect(c.progress.crystals, 150);

      // After the 400 ms lock the next deliberate tap buys again.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(buyButton('Crystal Value'));
      await tester.pump();
      expect(c.progress.level(UpgradeType.crystalValue), 2);
      expect(c.progress.crystals, 0);
    });

    test('a buy while the previous save is in flight is ignored', () async {
      final store = SlowStore();
      final c = makeController(crystals: 1000, store: store);
      final first = c.buyUpgrade(UpgradeType.shield);
      final second = await c.buyUpgrade(UpgradeType.magnet);
      expect(second, isFalse);
      expect(c.progress.level(UpgradeType.magnet), 0);

      store.pending.single.complete();
      expect(await first, isTrue);
      expect(c.progress.level(UpgradeType.shield), 1);

      // Once the first buy has finished, the next one goes through.
      final third = c.buyUpgrade(UpgradeType.magnet);
      store.pending.last.complete();
      expect(await third, isTrue);
      expect(c.progress.level(UpgradeType.magnet), 1);
    });
  });
}
