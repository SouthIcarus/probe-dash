// Probe Test Kit: the seams inside the game are inert in a normal build
// (acceptance A9), and the state logger prints what it should.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/config/env.dart';
import 'package:probe_dash/testkit/fault.dart';
import 'package:probe_dash/testkit/state_logger.dart';
import 'package:probe_dash/ui/game_screen.dart';

import '../support/fakes.dart';

void main() {
  group('A9 test-kit switch', () {
    test('off by default, on only for dev with TESTKIT=true', () {
      expect(const EnvConfig().testkitEnabled, isFalse);
      expect(const EnvConfig(testkit: 'true').testkitEnabled, isTrue);
      expect(const EnvConfig(testkit: 'TRUE').testkitEnabled, isFalse);
      expect(const EnvConfig(testkit: '1').testkitEnabled, isFalse);
    });

    test('beta and prod never enable it, whatever the define says', () {
      for (final flavor in ['beta', 'prod']) {
        expect(
            EnvConfig(flavorName: flavor, testkit: 'true').testkitEnabled,
            isFalse,
            reason: flavor);
      }
      // A mistyped flavor is dev (the safe choice), as for every other rule.
      expect(const EnvConfig(flavorName: 'nonsense', testkit: 'true')
          .testkitEnabled, isTrue);
    });

    test('this test build has the kit off, and the fault off', () {
      expect(env.testkitEnabled, isFalse);
      expect(TestkitFault.countRunsTwice, isFalse);
    });

    test('the fault is a switch that only this test turns on', () {
      TestkitFault.countRunsTwice = true;
      addTearDown(() => TestkitFault.countRunsTwice = false);
      expect(TestkitFault.countRunsTwice, isTrue);
    });

    testWidgets('a game with the kit off prints no PROBE_STATE line',
        (tester) async {
      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      try {
        final c = makeController();
        await tester.pumpWidget(MaterialApp(home: GameScreen(controller: c)));
        await tester.pump();
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        gameOf(tester).tapInput();
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      } finally {
        debugPrint = previous;
      }
      expect(lines.where((l) => l.contains('PROBE_STATE')), isEmpty);
    });
  });

  group('state logger', () {
    test('prints on a phase change and then once per second', () {
      final lines = <String>[];
      final logger = StateLogger(sink: lines.add);
      Map<String, Object?> state() => {'phase': 'x', 'n': lines.length};

      logger.tick(0.016, 'ready', state); // first call: phase is new
      expect(lines, hasLength(1));
      for (var i = 0; i < 30; i++) {
        logger.tick(0.016, 'ready', state); // 0.48 s: nothing
      }
      expect(lines, hasLength(1));
      for (var i = 0; i < 40; i++) {
        logger.tick(0.016, 'ready', state); // passes 1 s
      }
      expect(lines, hasLength(2));
      logger.tick(0.016, 'playing', state); // phase changed: prints at once
      expect(lines, hasLength(3));
    });

    test('each line is the prefix and one JSON object', () {
      final lines = <String>[];
      StateLogger(sink: lines.add)
          .tick(0, 'ready', () => {'phase': 'ready', 'distanceM': 0});
      expect(lines.single.startsWith('PROBE_STATE {'), isTrue);
      final json = jsonDecode(lines.single.substring('PROBE_STATE '.length));
      expect(json, {'phase': 'ready', 'distanceM': 0});
    });

    test('state is only built when a line is printed', () {
      var built = 0;
      final logger = StateLogger(sink: (_) {});
      logger.tick(0.016, 'ready', () {
        built++;
        return {};
      });
      logger.tick(0.016, 'ready', () {
        built++;
        return {};
      });
      expect(built, 1);
    });
  });
}
