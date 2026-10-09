import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/game/haptics.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/logic/upgrades.dart';
import 'package:probe_dash/ui/game_screen.dart';
import 'package:probe_dash/ui/upgrades_screen.dart';

import 'support/fakes.dart';

Finder buyButton(String name) => find.descendant(
    of: find.ancestor(
        of: find.textContaining(name), matching: find.byType(Card)),
    matching: find.byType(FilledButton));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGame(WidgetTester tester, c) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: c)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  group('A-29 haptic strength per event', () {
    HapticPattern p(HapticKind k) => Haptics.patterns[k]!;

    test('every event has a valid pattern', () {
      for (final k in HapticKind.values) {
        final pattern = p(k);
        expect(pattern.timings.length, pattern.amplitudes.length, reason: '$k');
        expect(pattern.timings.every((t) => t >= 0), isTrue, reason: '$k');
        expect(pattern.amplitudes.every((a) => a >= 0 && a <= 255), isTrue,
            reason: '$k');
        expect(pattern.onMillis, greaterThan(0), reason: '$k');
      }
    });

    test('crash is one strong buzz: full strength, 60-100 ms', () {
      final crash = p(HapticKind.crash);
      expect(crash.pulses, 1);
      expect(crash.peakAmplitude, 255);
      expect(crash.onMillis, inInclusiveRange(60, 100));
      for (final k in HapticKind.values.where((k) => k != HapticKind.crash)) {
        expect(p(k).peakAmplitude, lessThan(crash.peakAmplitude), reason: '$k');
      }
    });

    test('shield is medium, near miss and upgrade buy are light ticks', () {
      final shield = p(HapticKind.shieldHit);
      final near = p(HapticKind.nearMiss);
      final buy = p(HapticKind.upgradeBought);
      expect(shield.pulses, 1);
      expect(shield.peakAmplitude, greaterThan(near.peakAmplitude));
      expect(shield.onMillis, greaterThan(near.onMillis));
      expect(near.onMillis, lessThanOrEqualTo(25));
      expect(buy.onMillis, lessThanOrEqualTo(25));
      expect(buy.peakAmplitude, lessThan(shield.peakAmplitude));
    });

    test('new best is a medium double pulse', () {
      final best = p(HapticKind.newBest);
      expect(best.pulses, 2);
      expect(best.peakAmplitude, p(HapticKind.shieldHit).peakAmplitude);
    });
  });

  group('Android vibration channel', () {
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(
        PlatformHapticsBackend.channel, null));

    test('sends the event pattern to probe_dash/haptics', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(PlatformHapticsBackend.channel,
          (call) async {
        calls.add(call);
        return true;
      });
      const PlatformHapticsBackend().play(HapticKind.crash);
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'vibrate');
      expect(calls.single.arguments, {
        'timings': [0, 80],
        'amplitudes': [0, 255],
      });
    });

    test('no native side: MissingPluginException is swallowed', () async {
      const PlatformHapticsBackend().play(HapticKind.crash);
      await Future<void>.delayed(Duration.zero);
      // Reaching here without an uncaught error is the check.
    });

    test('native error: PlatformException is swallowed', () async {
      messenger.setMockMethodCallHandler(PlatformHapticsBackend.channel,
          (call) async => throw PlatformException(code: 'boom'));
      const PlatformHapticsBackend().play(HapticKind.shieldHit);
      await Future<void>.delayed(Duration.zero);
    });

    test('other platforms keep Flutter HapticFeedback', () async {
      final calls = <Object?>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments);
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        const PlatformHapticsBackend().play(HapticKind.crash);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['HapticFeedbackType.heavyImpact']);
    });
  });

  group('A-29 which event fires which haptic', () {
    testWidgets('crash: one crash haptic', (tester) async {
      final played = recordHaptics();
      await pumpGame(tester, makeController());
      await crashNow(tester);
      expect(gameOf(tester).phase.value, RunPhase.crashed);
      expect(played, [HapticKind.crash]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(played, [HapticKind.crash]); // still once
    });

    testWidgets('thrust taps and crystals: none', (tester) async {
      final played = recordHaptics();
      await pumpGame(tester, makeController());
      final g = gameOf(tester);
      for (var i = 0; i < 5; i++) {
        g.tapInput();
        g.session!.events.add(RunEvent.crystal);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(played, isEmpty);
    });

    testWidgets('passing the best: one new-best haptic', (tester) async {
      final played = recordHaptics();
      await pumpGame(tester, makeController(best: 5));
      final g = gameOf(tester);
      g.tapInput();
      g.session!.invincibleSeconds = 1e9;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(g.session!.passedBest, isTrue);
      expect(played.where((k) => k == HapticKind.newBest), hasLength(1));
      expect(played, isNot(contains(HapticKind.crash)));
    });

    testWidgets('first run ever (best 0): no new-best haptic', (tester) async {
      final played = recordHaptics();
      await pumpGame(tester, makeController(best: 0));
      final g = gameOf(tester);
      g.tapInput();
      g.session!.invincibleSeconds = 1e9;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(played, isNot(contains(HapticKind.newBest)));
    });

    testWidgets('switch off silences the new-best haptic too',
        (tester) async {
      final played = recordHaptics();
      Haptics.enabled = false;
      addTearDown(() => Haptics.enabled = true);
      await pumpGame(tester, makeController(best: 5));
      final g = gameOf(tester);
      g.tapInput();
      g.session!.invincibleSeconds = 1e9;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(g.session!.passedBest, isTrue);
      expect(played, isEmpty);
    });

    testWidgets('upgrade buy: one light tick per level bought',
        (tester) async {
      final played = recordHaptics();
      final c = makeController(crystals: 250);
      await tester.pumpWidget(MaterialApp(home: UpgradesScreen(controller: c)));
      await tester.tap(buyButton('Crystal Value'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(buyButton('Crystal Value')); // inside the 400 ms lock
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.progress.level(UpgradeType.crystalValue), 1);
      expect(played, [HapticKind.upgradeBought]);
    });

    testWidgets('upgrade not affordable: no haptic', (tester) async {
      final played = recordHaptics();
      final c = makeController(crystals: 50);
      await tester.pumpWidget(MaterialApp(home: UpgradesScreen(controller: c)));
      await tester.tap(buyButton('Crystal Value'), warnIfMissed: false);
      await tester.pump();
      expect(c.progress.level(UpgradeType.crystalValue), 0);
      expect(played, isEmpty);
    });
  });
}
