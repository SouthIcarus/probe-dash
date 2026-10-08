import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/logic/tuning.dart';
import 'package:probe_dash/logic/upgrades.dart';

RunSession session({Map<UpgradeType, int> levels = const {}, int seed = 1}) =>
    RunSession(worldWidth: 180, upgradeLevels: levels, seed: seed);

/// Runs the simulation for [seconds], tapping whenever the probe drops
/// below the next gap's centre (a simple "bot" that flies well).
void flyFor(RunSession s, double seconds, {bool bot = true}) {
  const dt = 1 / 60;
  for (var t = 0.0; t < seconds && s.phase == RunPhase.playing; t += dt) {
    if (bot) {
      final ahead = s.gates
          .where((g) => g.x + Tuning.gateWidth > s.probeWorldX)
          .toList();
      final target =
          ahead.isEmpty ? Tuning.worldHeight / 2 : ahead.first.gapCenter;
      if (s.probeY > target + 7 && s.velocityY > 0) s.tap();
    }
    s.update(dt);
  }
}

void main() {
  group('GAME-1 physics', () {
    test('nothing moves before the first tap', () {
      final s = session();
      s.update(1);
      expect(s.phase, RunPhase.ready);
      expect(s.scroll, 0);
    });

    test('first tap starts the run and thrusts upward', () {
      final s = session();
      s.tap();
      expect(s.phase, RunPhase.playing);
      expect(s.velocityY, Tuning.thrustVelocity);
    });

    test('without taps the probe falls and crashes on the floor', () {
      final s = session()..tap();
      flyFor(s, 5, bot: false);
      expect(s.phase, RunPhase.crashed);
    });

    test('hitting the ceiling does not crash', () {
      final s = session()..tap();
      for (var i = 0; i < 40; i++) {
        s.tap();
        s.update(1 / 60);
      }
      expect(s.phase, RunPhase.playing);
      expect(s.probeY, greaterThanOrEqualTo(Tuning.probeRadius));
    });

    test('frame rate does not change the simulation (fixed time step)', () {
      final a = session(seed: 7)..tap();
      final b = session(seed: 7)..tap();
      for (var i = 0; i < 30; i++) {
        a.update(1 / 60);
      }
      for (var i = 0; i < 15; i++) {
        b.update(1 / 30);
      }
      expect(b.scroll, closeTo(a.scroll, 1e-9));
      expect(b.probeY, closeTo(a.probeY, 1e-9));
    });
  });

  group('GAME-2 passable gates', () {
    test('every gate is wide enough, inside the screen, and reachable', () {
      final s = session(seed: 42)..tap();
      s.invincibleSeconds = 1e9; // fly through everything to see 1000s of m
      final seen = <Gate>[];
      const dt = 1 / 60;
      for (var t = 0.0; t < 120; t += dt) {
        if (s.probeY > Tuning.worldHeight * 0.6) s.tap();
        s.update(dt);
        for (final g in s.gates) {
          if (!seen.contains(g)) seen.add(g);
        }
      }
      expect(s.distanceMeters, greaterThan(3000));
      expect(seen.length, greaterThan(50));
      for (var i = 0; i < seen.length; i++) {
        final g = seen[i];
        expect(g.gapHeight,
            greaterThanOrEqualTo(2.5 * 2 * Tuning.probeRadius));
        expect(g.gapHeight, greaterThanOrEqualTo(Tuning.minGap));
        expect(g.gapTop, greaterThanOrEqualTo(Tuning.edgeMargin - 1e-9));
        expect(g.gapBottom,
            lessThanOrEqualTo(Tuning.worldHeight - Tuning.edgeMargin + 1e-9));
        if (i > 0) {
          expect((g.gapCenter - seen[i - 1].gapCenter).abs(),
              lessThanOrEqualTo(Tuning.maxGapShift + 1e-9));
        }
      }
    });

    test('difficulty ramps: faster and tighter further in', () {
      final s = session();
      final speed0 = s.speed;
      final gap0 = s.gapForDistance;
      s.scroll = 3000 / Tuning.metersPerUnit;
      expect(s.speed, greaterThan(speed0));
      expect(s.gapForDistance, lessThan(gap0));
      expect(s.speed, lessThanOrEqualTo(Tuning.maxSpeed));
    });

    test('a good player gets through many gates', () {
      final s = session(seed: 3)..tap();
      flyFor(s, 30);
      expect(s.gatesPassed, greaterThan(5));
      expect(s.distanceMeters, greaterThan(200));
    });
  });

  group('Shield', () {
    test('Lv1 shield absorbs one floor hit, then grants grace time', () {
      final s = session(levels: {UpgradeType.shield: 1})..tap();
      expect(s.shieldHitsLeft, 1);
      flyFor(s, 3, bot: false);
      // Grace then second floor hit crashes.
      expect(s.shieldHitsLeft, 0);
      flyFor(s, 10, bot: false);
      expect(s.phase, RunPhase.crashed);
    });

    test('hit counts follow the spec thresholds', () {
      expect(Upgrades.shieldHits(0), 0);
      expect(Upgrades.shieldHits(1), 1);
      expect(Upgrades.shieldHits(4), 1);
      expect(Upgrades.shieldHits(5), 2);
      expect(Upgrades.shieldHits(9), 2);
      expect(Upgrades.shieldHits(10), 3);
      expect(Upgrades.shieldGraceSeconds(4),
          greaterThan(Upgrades.shieldGraceSeconds(3)));
    });
  });

  group('Revive (US-1)', () {
    test('revive once: continue invincible, second crash cannot revive', () {
      final s = session()..tap();
      flyFor(s, 5, bot: false);
      expect(s.phase, RunPhase.crashed);
      expect(s.canRevive, isTrue);

      s.revive();
      expect(s.phase, RunPhase.playing);
      expect(s.invincible, isTrue);
      expect(s.probeY, closeTo(Tuning.worldHeight / 2, 1e-9));

      flyFor(s, 10, bot: false);
      expect(s.phase, RunPhase.crashed);
      expect(s.canRevive, isFalse);
      s.revive(); // ignored
      expect(s.phase, RunPhase.crashed);
      expect(s.finish().revived, isTrue);
    });
  });

  group('Head start', () {
    test('no gates and no crash during the head start', () {
      final s = session(levels: {UpgradeType.headStart: 2})..tap();
      expect(s.inHeadStart, isTrue);
      const dt = 1 / 60;
      while (s.inHeadStart) {
        s.update(dt);
        expect(s.phase, RunPhase.playing);
      }
      expect(s.distanceMeters, greaterThanOrEqualTo(100));
      expect(s.gates.every((g) => g.x > s.probeWorldX), isTrue);
    });
  });

  group('Pickups', () {
    test('touching a crystal collects it', () {
      final s = session()..tap();
      s.pickups.add(Pickup(PickupKind.crystal, s.probeWorldX, s.probeY));
      s.update(Tuning.fixedStep);
      expect(s.rawCrystals, 1);
    });

    test('magnet pickup starts the magnet for the upgraded duration', () {
      final s = session(levels: {UpgradeType.magnet: 4})..tap();
      s.pickups.add(Pickup(PickupKind.magnet, s.probeWorldX, s.probeY));
      s.update(Tuning.fixedStep);
      expect(s.magnetSeconds, closeTo(Upgrades.magnetSeconds(4), 0.02));
    });

    test('magnet pulls nearby crystals in', () {
      final s = session()..tap();
      s.magnetSeconds = 5;
      final c = Pickup(PickupKind.crystal, s.probeWorldX + 15, s.probeY);
      s.pickups.add(c);
      s.update(0.3);
      expect(c.collected, isTrue);
    });
  });

  test('finish applies the crystal value multiplier', () {
    final s = session(levels: {UpgradeType.crystalValue: 5})..tap();
    s.rawCrystals = 10;
    final r = s.finish();
    expect(r.rawCrystals, 10);
    expect(r.earnedCrystals, 15);
    expect(s.phase, RunPhase.over);
  });

  test('A-20: finish twice returns the same result, not a recount', () {
    final s = session()..tap();
    s.rawCrystals = 4;
    final a = s.finish();
    s.rawCrystals = 99; // must not leak into the already-finished run
    final b = s.finish();
    expect(identical(a, b), isTrue);
    expect(b.rawCrystals, 4);
    expect(s.finished, isTrue);
    expect(s.phase, RunPhase.over);
  });
}
