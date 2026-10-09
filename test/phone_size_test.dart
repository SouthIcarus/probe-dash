import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/app/game_controller.dart';
import 'package:probe_dash/game/haptics.dart';
import 'package:probe_dash/game/probe_game.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/logic/tuning.dart';
import 'package:probe_dash/logic/upgrades.dart';
import 'package:probe_dash/ui/game_screen.dart';
import 'package:probe_dash/ui/home_screen.dart';
import 'package:probe_dash/ui/upgrades_screen.dart';

import 'support/fakes.dart';

/// A portrait phone as Flutter sees it: physical pixels, pixel ratio and
/// the camera-hole inset at the top (immersive: no status or nav bar).
class Phone {
  const Phone(this.name, this.physical, this.dpr, this.topInsetPx);

  final String name;
  final Size physical;
  final double dpr;
  final double topInsetPx;

  Size get logical => physical / dpr;

  void apply(WidgetTester tester) {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    tester.view.viewPadding = FakeViewPadding(top: topInsetPx);
    tester.view.padding = FakeViewPadding(top: topInsetPx);
    addTearDown(tester.view.reset);
  }
}

/// Galaxy S26 (1080 × 2340 px) at its common pixel ratios: about 411 × 891
/// and 360 × 780 logical pixels.
const phones = [
  Phone('S26 411x891', Size(1080, 2340), 1080 / 411, 84),
  Phone('S26 360x780', Size(1080, 2340), 3.0, 84),
];

Finder buyButton(String name) => find.descendant(
    of: find.ancestor(
        of: find.textContaining(name), matching: find.byType(Card)),
    matching: find.byType(FilledButton));

ThemeData get appTheme => ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF1E88E5),
      useMaterial3: true,
    );

Future<void> pumpGame(WidgetTester tester, GameController c,
    {double textScale = 1.0}) async {
  await tester.pumpWidget(MaterialApp(
    theme: appTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: GameScreen(controller: c),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

/// A run of [meters] that ends on the results screen (no revive offer).
Future<void> runTo(WidgetTester tester, int meters,
    {int crystals = 0, int nearMisses = 0}) async {
  final g = gameOf(tester);
  final s = g.session!;
  if (s.phase == RunPhase.ready) g.tapInput();
  s
    ..reviveUsed = true
    ..rawCrystals = crystals
    ..nearMisses = nearMisses
    ..scroll = meters / Tuning.metersPerUnit;
  await crashNow(tester);
  await waitForOverlay(tester);
  expect(find.text('PLAY AGAIN'), findsOneWidget);
}

void main() {
  for (final phone in phones) {
    group('S26 check 13 at ${phone.name}', () {
      testWidgets('upgrade shortcut: one line, hittable, opens Upgrades',
          (tester) async {
        phone.apply(tester);
        // A full results card: new best, 2× button, near misses, shortcut.
        final c = makeController(crystals: 120, ads: FakeAds(ready: true));
        await pumpGame(tester, c);
        await runTo(tester, 140, crystals: 9, nearMisses: 2);
        expect(tester.takeException(), isNull); // no RenderFlex overflow

        final label = find.text('Upgrade: Crystal Value Lv1 – 100 ◆');
        expect(label.hitTestable(), findsOneWidget);
        // One line (no wrapped "◆"), drawn inside its button.
        final para = tester.renderObject<RenderParagraph>(label);
        expect(para.getBoxesForSelection(TextSelection(
                    baseOffset: 0, extentOffset: para.text.toPlainText().length))
                .map((b) => b.top)
                .toSet(),
            hasLength(1));
        final button =
            find.ancestor(of: label, matching: find.byType(OutlinedButton));
        final labelRect = tester.getRect(label);
        final buttonRect = tester.getRect(button);
        expect(buttonRect.contains(labelRect.topLeft), isTrue);
        expect(buttonRect.contains(labelRect.bottomRight), isTrue);
        final rect = tester.getRect(button);
        final screen = Offset.zero & phone.logical;
        expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight),
            isTrue,
            reason: 'shortcut $rect must be fully on a ${phone.logical} screen');

        // Tap near the button's left edge, not just the label's centre.
        await tester.tapAt(rect.centerLeft + const Offset(6, 0));
        await settle(tester);
        expect(find.byType(UpgradesScreen), findsOneWidget);
      });

      testWidgets('"Upgrades" text button opens Upgrades; back returns',
          (tester) async {
        phone.apply(tester);
        final c = makeController(crystals: 0);
        await pumpGame(tester, c);
        await runTo(tester, 40);
        expect(find.text('Upgrades').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Upgrades'));
        await settle(tester);
        expect(find.byType(UpgradesScreen), findsOneWidget);
        await tester.pageBack();
        await settle(tester);
        expect(find.byType(UpgradesScreen), findsNothing);
        expect(find.text('PLAY AGAIN').hitTestable(), findsOneWidget);
      });

      testWidgets('Buy buttons: a fast double tap buys exactly one level',
          (tester) async {
        phone.apply(tester);
        final c = makeController(crystals: 250);
        await pumpGame(tester, c);
        await runTo(tester, 40);
        await tester.tap(find.textContaining('Upgrade:'));
        await settle(tester);

        for (final u in Upgrades.all) {
          expect(buyButton(u.name).hitTestable(), findsOneWidget,
              reason: u.name);
        }
        await tester.tap(buyButton('Crystal Value'));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tap(buyButton('Crystal Value'));
        await tester.pump(const Duration(milliseconds: 80));
        expect(c.progress.level(UpgradeType.crystalValue), 1);
        expect(c.progress.crystals, 150);

        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(buyButton('Crystal Value'));
        await tester.pump();
        expect(c.progress.level(UpgradeType.crystalValue), 2);
        expect(c.progress.crystals, 0);
      });

      testWidgets('large system font (2×): no overflow, buttons reachable',
          (tester) async {
        phone.apply(tester);
        final c = makeController(crystals: 120, ads: FakeAds(ready: true));
        await pumpGame(tester, c, textScale: 2.0);
        await runTo(tester, 140, crystals: 9, nearMisses: 2);
        expect(tester.takeException(), isNull);
        final label = find.textContaining('Upgrade:');
        await tester.ensureVisible(label);
        await tester.pump();
        expect(label.hitTestable(), findsOneWidget);
        await tester.tap(label);
        await settle(tester);
        expect(find.byType(UpgradesScreen), findsOneWidget);
      });
    });

    group('S26 check 9 at ${phone.name}', () {
      testWidgets('first run sets the best; Play again and beat it: banner, '
          'HUD and results all say NEW BEST', (tester) async {
        phone.apply(tester);
        final played = recordHaptics();
        final c = makeController(best: 0);
        await pumpGame(tester, c);
        final g = gameOf(tester);

        // Run 1, first ever: no banner (there was no best to chase), but
        // results say NEW BEST! because 60 m > 0.
        g.tapInput();
        g.session!.invincibleSeconds = 1e9;
        await tester.pump(const Duration(milliseconds: 16));
        expect(g.newBestBannerAge, isNull);
        g.session!.invincibleSeconds = 0;
        await runTo(tester, 60);
        expect(find.text('NEW BEST!'), findsOneWidget);
        expect(c.progress.bestDistance, 60);
        expect(played, isNot(contains(HapticKind.newBest)));

        // Run 2 on the same game: the best is carried over.
        await tester.tap(find.text('PLAY AGAIN'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(identical(gameOf(tester), g), isTrue);
        expect(g.bestDistance, 60);
        expect(ProbeGame.bestLine(g.bestDistance, passed: false), 'BEST 60 m');

        g.tapInput();
        final s = g.session!..invincibleSeconds = 1e9;
        // Approach: 10 m short, the gold line is on screen ahead of the
        // probe and its label is inside the screen width.
        s.scroll = 50 / Tuning.metersPerUnit;
        await tester.pump(const Duration(milliseconds: 16));
        final worldWidth = g.size.x / (g.size.y / Tuning.worldHeight);
        final x = g.bestMarkerWorldX;
        expect(x, isNotNull);
        expect(x!, greaterThan(s.probeX));
        expect(x, lessThan(worldWidth));
        expect(s.passedBest, isFalse);
        expect(g.newBestBannerAge, isNull);

        // Fly past it.
        s.scroll = 61.5 / Tuning.metersPerUnit;
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(s.passedBest, isTrue);
        expect(g.newBestBannerAge, isNotNull);
        expect(ProbeGame.bannerAlpha(g.newBestBannerAge!), 1.0);
        final anchor = g.newBestBannerAnchor;
        expect((Offset.zero & Size(g.size.x, g.size.y)).contains(anchor), isTrue);
        expect(anchor.dy, greaterThan(g.hudTop)); // below the HUD lines
        expect(ProbeGame.bestLine(g.bestDistance, passed: s.passedBest),
            'NEW BEST');
        expect(played.where((k) => k == HapticKind.newBest), hasLength(1));

        // Crash: results say NEW BEST! and the best is saved.
        s.invincibleSeconds = 0;
        await runTo(tester, 75);
        expect(find.text('NEW BEST!'), findsOneWidget);
        expect(c.progress.bestDistance, 75);
      });

      testWidgets('equal to the best is not a new best, in run or results',
          (tester) async {
        phone.apply(tester);
        final c = makeController(best: 60);
        await pumpGame(tester, c);
        final g = gameOf(tester);
        g.tapInput();
        final s = g.session!..invincibleSeconds = 1e9;
        s.scroll = 60 / Tuning.metersPerUnit;
        // One physics step: 60.16 m, which floors to 60 (not past 60).
        await tester.pump(const Duration(milliseconds: 9));
        expect(s.distanceMeters, greaterThan(60));
        expect(s.passedBest, isFalse);
        s.invincibleSeconds = 0;
        await runTo(tester, 60);
        expect(find.text('NEW BEST!'), findsNothing);
        expect(c.progress.bestDistance, 60);
      });
    });
  }

  testWidgets('S26 check 9: Home → new game carries the best', (tester) async {
    phones.first.apply(tester);
    final c = makeController(best: 0);
    await tester.pumpWidget(
        MaterialApp(theme: appTheme, home: HomeScreen(controller: c)));
    await tester.tap(find.text('PLAY'));
    await settle(tester);
    await runTo(tester, 30);
    expect(find.text('NEW BEST!'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await settle(tester);
    expect(find.text('Best: 30 m'), findsOneWidget);

    await tester.tap(find.text('PLAY'));
    await settle(tester);
    final g = gameOf(tester);
    expect(g.bestDistance, 30);
    g.tapInput();
    final s = g.session!..invincibleSeconds = 1e9;
    s.scroll = 31.5 / Tuning.metersPerUnit;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(s.passedBest, isTrue);
    expect(g.newBestBannerAge, isNotNull);
  });

  testWidgets('A-27: results at 2× font on an 800 × 360 surface: no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = makeController(crystals: 120, ads: FakeAds(ready: true));
    await pumpGame(tester, c, textScale: 2.0);
    await runTo(tester, 140, crystals: 9, nearMisses: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Home'));
    await tester.pump();
    expect(find.text('Home').hitTestable(), findsOneWidget);
  });

  group('A-22 a stuck save never blocks later buys', () {
    testWidgets('buys are ignored while saving, allowed again after 2 s',
        (tester) async {
      final store = SlowStore(); // its saves never finish on their own
      final c = makeController(crystals: 1000, store: store);
      final first = c.buyUpgrade(UpgradeType.shield);
      expect(c.progress.level(UpgradeType.shield), 1); // applied at once
      expect(await c.buyUpgrade(UpgradeType.magnet), isFalse); // in flight

      await tester.pump(GameController.buySaveWaitLimit);
      expect(await first, isTrue);
      final second = c.buyUpgrade(UpgradeType.magnet);
      expect(c.progress.level(UpgradeType.magnet), 1);
      await tester.pump(GameController.buySaveWaitLimit);
      expect(await second, isTrue);
      expect(store.saves, 2); // both still queued for saving
    });
  });
}
