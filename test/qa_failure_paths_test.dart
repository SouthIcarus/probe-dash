// QA failure-path tests for UX PR 1 (qa-engineer). Each test names the
// failure it guards against; see changelog #0019.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/game/haptics.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/logic/upgrades.dart';
import 'package:probe_dash/services/ad_service.dart';
import 'package:probe_dash/ui/game_screen.dart';

import 'support/fakes.dart';

/// A rewarded ad that stays "on screen" until the test completes [open].
class HeldAds extends FakeAds {
  HeldAds() : super(ready: true);

  Completer<RewardedOutcome>? open;

  @override
  Future<RewardedOutcome> showRewarded() {
    rewardedShown++;
    return (open = Completer<RewardedOutcome>()).future;
  }
}

void main() {
  Future<void> pumpGame(WidgetTester tester, c) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: c)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  Future<void> pushGame(WidgetTester tester, c) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => GameScreen(controller: c))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Records platform-channel calls by method name.
  List<String> recordPlatform(WidgetTester tester, String method) {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == method) calls.add('${call.arguments}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return calls;
  }

  group('QA revive paths', () {
    testWidgets('revive, then a second crash goes to results with no offer',
        (tester) async {
      final ads = FakeAds(ready: true, watchResult: true);
      final c = makeController(ads: ads);
      await pumpGame(tester, c);
      gameOf(tester).session!.rawCrystals = 6;
      await crashNow(tester);
      await waitForOverlay(tester);
      await tester.tap(find.text('Watch ad to revive'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(ads.rewardedShown, 1);
      expect(gameOf(tester).phase.value, RunPhase.playing);
      expect(find.text('CONTINUE?'), findsNothing);
      expect(c.progress.runs, 0);

      // Second crash after the revive shield has run out.
      gameOf(tester).session!.invincibleSeconds = 0;
      await crashNow(tester);
      expect(gameOf(tester).phase.value, RunPhase.crashed);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PLAY AGAIN'), findsNothing); // beat plays again
      await waitForOverlay(tester);
      expect(find.text('CONTINUE?'), findsNothing); // once per run
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(ads.rewardedShown, 1);
      expect(c.progress.runs, 1);
      expect(c.progress.crystals, 6);
    });

    testWidgets('countdown stays paused while the revive ad is open',
        (tester) async {
      final ads = HeldAds();
      final c = makeController(ads: ads);
      await pumpGame(tester, c);
      await crashNow(tester);
      await waitForOverlay(tester);
      await tester.tap(find.text('Watch ad to revive'));
      await tester.pump(const Duration(milliseconds: 16));

      // The ad stays open longer than the whole 5 s countdown.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(c.progress.runs, 0); // countdown did not decline behind the ad
      expect(find.text('PLAY AGAIN'), findsNothing);

      ads.open!.complete(RewardedOutcome.earned);
      await tester.pump(const Duration(milliseconds: 16));
      expect(gameOf(tester).phase.value, RunPhase.playing);
      expect(c.progress.runs, 0);
    });

    testWidgets('back while the revive ad is open is ignored',
        (tester) async {
      final ads = HeldAds();
      final c = makeController(ads: ads);
      await pushGame(tester, c);
      await crashNow(tester);
      await waitForOverlay(tester);
      await tester.tap(find.text('Watch ad to revive'));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GameScreen), findsOneWidget);
      expect(c.progress.runs, 0);

      ads.open!.complete(RewardedOutcome.earned);
      await tester.pump(const Duration(milliseconds: 16));
      expect(gameOf(tester).phase.value, RunPhase.playing);
    });
  });

  group('QA back gesture', () {
    testWidgets('back during the crash beat saves once, no late offer',
        (tester) async {
      final c = makeController(ads: FakeAds(ready: true));
      await pushGame(tester, c);
      gameOf(tester).session!.rawCrystals = 3;
      await crashNow(tester);
      await tester.pump(const Duration(milliseconds: 200)); // inside the beat
      expect(find.text('CONTINUE?'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(GameScreen), findsOneWidget);
      expect(c.progress.runs, 1);
      expect(c.progress.crystals, 3);

      // The beat's timer must not bring the revive offer up afterwards.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('CONTINUE?'), findsNothing);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(c.progress.runs, 1);
    });

    testWidgets('leaving by back restores edge-to-edge (before first tap)',
        (tester) async {
      final modes = recordPlatform(tester, 'SystemChrome.setEnabledSystemUIMode');
      await pushGame(tester, makeController());
      expect(modes, ['SystemUiMode.immersiveSticky']);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
      expect(modes.last, 'SystemUiMode.edgeToEdge');
    });

    testWidgets('leaving results by back restores edge-to-edge',
        (tester) async {
      final modes = recordPlatform(tester, 'SystemChrome.setEnabledSystemUIMode');
      final c = makeController();
      await pushGame(tester, c);
      g() => gameOf(tester);
      g().tapInput();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.binding.handlePopRoute(); // mid-run: results
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(modes, ['SystemUiMode.immersiveSticky']); // still immersive
      await tester.binding.handlePopRoute(); // results: leave
      await settle(tester);
      expect(find.byType(GameScreen), findsNothing);
      expect(modes.last, 'SystemUiMode.edgeToEdge');
    });
  });

  group('QA overlay lock', () {
    testWidgets('PLAY AGAIN during the lock: no restart; after it: restart',
        (tester) async {
      final c = makeController();
      await pumpGame(tester, c);
      gameOf(tester).session!.reviveUsed = true;
      await crashNow(tester);
      await tester.pump(const Duration(milliseconds: 600)); // results up
      final first = gameOf(tester).session;
      // Panel up ~100 ms; tap at ~100, ~200 and ~300 ms: all inside the
      // 400 ms lock, as a player still tapping from the run would.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('PLAY AGAIN'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Taps fell through to the game: the finished run must stay finished.
      expect(identical(gameOf(tester).session, first), isTrue);
      expect(gameOf(tester).phase.value, RunPhase.over);
      expect(c.progress.runs, 1);

      await tester.pump(const Duration(milliseconds: 200)); // lock over
      await tester.tap(find.text('PLAY AGAIN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('PLAY AGAIN'), findsNothing);
      expect(gameOf(tester).phase.value, RunPhase.ready);
      expect(c.progress.runs, 1);
    });
  });

  group('QA upgrade shortcut boundary', () {
    testWidgets('crystals exactly equal to the cost show the shortcut',
        (tester) async {
      final c = makeController(crystals: 100); // Crystal Value Lv1 = 100
      await pumpGame(tester, c);
      gameOf(tester).session!.reviveUsed = true;
      await crashNow(tester);
      await waitForOverlay(tester);
      expect(c.progress.crystals, 100);
      expect(find.text('Upgrade: Crystal Value Lv1 – 100 ◆'),
          findsOneWidget);
    });

    testWidgets('one crystal short: no shortcut', (tester) async {
      final c = makeController(crystals: 99);
      await pumpGame(tester, c);
      gameOf(tester).session!.reviveUsed = true;
      await crashNow(tester);
      await waitForOverlay(tester);
      expect(find.textContaining('Upgrade:'), findsNothing);
    });

    test('pure helper: equal is affordable, one short is not', () {
      final o = Upgrades.cheapestAffordable(const {}, 100);
      expect(o?.cost, 100);
      expect(Upgrades.cheapestAffordable(const {}, 99), isNull);
    });
  });

  group('QA haptics per event', () {
    testWidgets('shield absorb: one shield haptic, no crash haptic',
        (tester) async {
      final vib = recordHaptics();
      final c = makeController();
      c.progress.upgrades[UpgradeType.shield] = 1;
      await pumpGame(tester, c);
      await crashNow(tester);
      expect(gameOf(tester).phase.value, RunPhase.playing); // absorbed
      expect(vib, [HapticKind.shieldHit]);
    });

    testWidgets('near miss: light tick, max one per 300 ms',
        (tester) async {
      final vib = recordHaptics();
      await pumpGame(tester, makeController());
      final g = gameOf(tester);
      g.tapInput();
      g.session!.invincibleSeconds = 1e9;
      g.session!.events.add(RunEvent.nearMiss);
      await tester.pump(const Duration(milliseconds: 16));
      g.session!.events.add(RunEvent.nearMiss); // ~16 ms later
      await tester.pump(const Duration(milliseconds: 16));
      expect(vib, [HapticKind.nearMiss]);

      await tester.pump(const Duration(milliseconds: 320));
      g.session!.events.add(RunEvent.nearMiss);
      await tester.pump(const Duration(milliseconds: 16));
      expect(vib, [HapticKind.nearMiss, HapticKind.nearMiss]);
    });

    testWidgets('switch off: no haptic for crash, shield or near miss',
        (tester) async {
      final vib = recordHaptics();
      Haptics.enabled = false;
      addTearDown(() => Haptics.enabled = true);
      final c = makeController();
      c.progress.upgrades[UpgradeType.shield] = 1;
      await pumpGame(tester, c);
      final g = gameOf(tester);
      await crashNow(tester); // shield hit
      g.session!.events.add(RunEvent.nearMiss);
      // Wait out the 80 ms shield hit-stop (physics is paused during it).
      await tester.pump(const Duration(milliseconds: 100));
      g.session!
        ..invincibleSeconds = 0
        ..shieldHitsLeft = 0;
      await crashNow(tester); // crash
      expect(g.phase.value, RunPhase.crashed);
      expect(vib, isEmpty);
    });

    testWidgets('no haptic on thrust taps or crystals', (tester) async {
      final vib = recordHaptics();
      await pumpGame(tester, makeController());
      final g = gameOf(tester);
      for (var i = 0; i < 5; i++) {
        g.tapInput();
        g.session!.events.add(RunEvent.crystal);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(vib, isEmpty);
    });
  });
}
