import 'dart:math' as math;

import 'tuning.dart';
import 'upgrades.dart';

/// Run state machine (spec §7 "Run"). `crashed` covers both the Crashed
/// and ReviveOffer states: the UI decides whether a revive can be offered.
enum RunPhase { ready, playing, crashed, over }

class Gate {
  Gate(this.x, this.gapCenter, this.gapHeight);

  /// World x of the gate's left edge.
  final double x;
  final double gapCenter;
  final double gapHeight;

  double get gapTop => gapCenter - gapHeight / 2;
  double get gapBottom => gapCenter + gapHeight / 2;

  bool passed = false;
  bool hit = false;
  double minClearance = double.infinity;
}

enum PickupKind { crystal, magnet }

class Pickup {
  Pickup(this.kind, this.x, this.y);

  final PickupKind kind;
  double x;
  double y;
  bool collected = false;
}

class RunResult {
  const RunResult({
    required this.distanceMeters,
    required this.rawCrystals,
    required this.earnedCrystals,
    required this.nearMisses,
    required this.revived,
  });

  final int distanceMeters;
  final int rawCrystals;
  final int earnedCrystals;
  final int nearMisses;
  final bool revived;
}

/// One run of the game, as pure logic: no Flutter, no rendering.
///
/// Coordinates: y = 0 is the top of the playfield, [Tuning.worldHeight] the
/// bottom. Entity x values are world positions; the probe sits at
/// `scroll + probeX`. Screen x = world x − [scroll].
class RunSession {
  RunSession({
    required this.worldWidth,
    required Map<UpgradeType, int> upgradeLevels,
    int? seed,
  })  : _levels = Map.of(upgradeLevels),
        _random = math.Random(seed) {
    probeX = worldWidth * Tuning.probeXFraction;
    probeY = Tuning.worldHeight / 2;
    shieldHitsLeft = Upgrades.shieldHits(_level(UpgradeType.shield));
    _headStartUnits =
        Upgrades.headStartMeters(_level(UpgradeType.headStart)) /
            Tuning.metersPerUnit;
    _nextGateX = _headStartUnits + probeX + worldWidth * 0.75;
    _lastGapCenter = Tuning.worldHeight / 2;
  }

  final double worldWidth;
  final Map<UpgradeType, int> _levels;
  final math.Random _random;

  RunPhase phase = RunPhase.ready;
  late final double probeX;
  late double probeY;
  double velocityY = 0;
  double scroll = 0;

  final List<Gate> gates = [];
  final List<Pickup> pickups = [];

  int rawCrystals = 0;
  int nearMisses = 0;
  int gatesPassed = 0;
  late int shieldHitsLeft;
  double invincibleSeconds = 0;
  double magnetSeconds = 0;
  bool reviveUsed = false;

  /// Seconds since the last tap; the renderer uses it for the thruster flame.
  double sinceTap = 99;

  late final double _headStartUnits;
  late double _nextGateX;
  late double _lastGapCenter;
  double _nextMagnetMeters = Tuning.magnetPickupEveryMeters;
  double _accumulator = 0;

  int _level(UpgradeType t) => _levels[t] ?? 0;

  double get distanceMeters => scroll * Tuning.metersPerUnit;
  double get probeWorldX => scroll + probeX;
  bool get inHeadStart => scroll < _headStartUnits;
  bool get invincible => inHeadStart || invincibleSeconds > 0;
  bool get canRevive => !reviveUsed;

  double get speed {
    final base = math.min(
        Tuning.maxSpeed, Tuning.startSpeed + distanceMeters / 60);
    return inHeadStart ? base * Tuning.headStartSpeedFactor : base;
  }

  double get gapForDistance =>
      math.max(Tuning.minGap, Tuning.startGap - distanceMeters / 150);

  double get spacingForDistance => math.max(
      Tuning.minSpacing, Tuning.startSpacing - distanceMeters / 120);

  void tap() {
    switch (phase) {
      case RunPhase.ready:
        phase = RunPhase.playing;
        _thrust();
      case RunPhase.playing:
        if (!inHeadStart) _thrust();
      case RunPhase.crashed:
      case RunPhase.over:
        break;
    }
  }

  void _thrust() {
    velocityY = Tuning.thrustVelocity;
    sinceTap = 0;
  }

  /// Advances the simulation by [dt] seconds in fixed steps, so physics is
  /// identical regardless of frame rate (GAME-1).
  void update(double dt) {
    if (phase != RunPhase.playing) return;
    _accumulator += math.min(dt, 0.25); // avoid a spiral after a long pause
    while (_accumulator >= Tuning.fixedStep && phase == RunPhase.playing) {
      _step(Tuning.fixedStep);
      _accumulator -= Tuning.fixedStep;
    }
  }

  void _step(double h) {
    sinceTap += h;
    scroll += speed * h;

    if (inHeadStart) {
      // Autopilot: glide to the middle while rocketing forward.
      probeY += (Tuning.worldHeight / 2 - probeY) * math.min(1, 4 * h);
      velocityY = 0;
    } else {
      velocityY =
          math.min(Tuning.maxFallSpeed, velocityY + Tuning.gravity * h);
      probeY += velocityY * h;
    }

    if (probeY < Tuning.probeRadius) {
      probeY = Tuning.probeRadius; // ceiling stops you, it doesn't kill
      velocityY = 0;
    }

    if (probeY > Tuning.worldHeight - Tuning.probeRadius) {
      probeY = Tuning.worldHeight - Tuning.probeRadius;
      if (!invincible) _hit();
      if (phase == RunPhase.playing) _thrust(); // bounce off the floor
    }

    _spawn();
    _checkGates();
    _updatePickups(h);

    if (invincibleSeconds > 0) invincibleSeconds -= h;
    if (magnetSeconds > 0) magnetSeconds -= h;
  }

  void _spawn() {
    while (_nextGateX < scroll + worldWidth + Tuning.gateWidth * 2) {
      final gap = gapForDistance;
      final minC = Tuning.edgeMargin + gap / 2;
      final maxC = Tuning.worldHeight - Tuning.edgeMargin - gap / 2;
      final low = math.max(minC, _lastGapCenter - Tuning.maxGapShift);
      final high = math.min(maxC, _lastGapCenter + Tuning.maxGapShift);
      final center = low + _random.nextDouble() * (high - low);

      final gate = Gate(_nextGateX, center, gap);
      gates.add(gate);

      final gateMeters = _nextGateX * Tuning.metersPerUnit;
      final midX = _nextGateX + Tuning.gateWidth / 2;
      if (gateMeters >= _nextMagnetMeters) {
        pickups.add(Pickup(PickupKind.magnet, midX, center));
        _nextMagnetMeters += Tuning.magnetPickupEveryMeters;
      } else if (_random.nextDouble() < 0.7) {
        pickups.add(Pickup(PickupKind.crystal, midX, center));
      }

      // A short trail of crystals leading into the next gate, along a line
      // the probe can actually fly.
      final spacing = spacingForDistance;
      if (gates.length > 1 && _random.nextDouble() < 0.5) {
        final startX = _nextGateX - spacing / 2 - 6;
        for (var i = 0; i < 3; i++) {
          final t = (i + 1) / 4;
          pickups.add(Pickup(PickupKind.crystal, startX + i * 6,
              _lastGapCenter + (center - _lastGapCenter) * t));
        }
      }

      _lastGapCenter = center;
      _nextGateX += spacing + Tuning.gateWidth;
    }

    gates.removeWhere((g) => g.x + Tuning.gateWidth < scroll - 10);
    pickups.removeWhere((p) => p.collected || p.x < scroll - 10);
  }

  void _checkGates() {
    final px = probeWorldX;
    const r = Tuning.probeRadius;
    for (final gate in gates) {
      final overlapsX = px + r > gate.x && px - r < gate.x + Tuning.gateWidth;
      if (overlapsX && !gate.hit) {
        final clearance = math.min(
            probeY - r - gate.gapTop, gate.gapBottom - (probeY + r));
        gate.minClearance = math.min(gate.minClearance, clearance);
        if (!invincible &&
            (_circleHitsRect(px, probeY, r, gate.x, 0, Tuning.gateWidth,
                    gate.gapTop) ||
                _circleHitsRect(px, probeY, r, gate.x, gate.gapBottom,
                    Tuning.gateWidth, Tuning.worldHeight - gate.gapBottom))) {
          gate.hit = true;
          _hit();
          if (phase != RunPhase.playing) return;
        }
      }
      if (!gate.passed && px - r > gate.x + Tuning.gateWidth) {
        gate.passed = true;
        gatesPassed++;
        if (!gate.hit &&
            gate.minClearance >= 0 &&
            gate.minClearance < Tuning.nearMissDistance) {
          nearMisses++;
          rawCrystals += Tuning.nearMissBonus;
        }
      }
    }
  }

  void _updatePickups(double h) {
    final px = probeWorldX;
    final magnetOn = magnetSeconds > 0;
    for (final p in pickups) {
      if (p.collected) continue;
      final dx = px - p.x;
      final dy = probeY - p.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (magnetOn &&
          p.kind == PickupKind.crystal &&
          dist < Tuning.magnetRadius &&
          dist > 0) {
        final pull = math.min(dist, 120 * h);
        p.x += dx / dist * pull;
        p.y += dy / dist * pull;
      }
      if (dist < Tuning.probeRadius + Tuning.crystalRadius) {
        p.collected = true;
        if (p.kind == PickupKind.crystal) {
          rawCrystals++;
        } else {
          magnetSeconds =
              Upgrades.magnetSeconds(_level(UpgradeType.magnet));
        }
      }
    }
  }

  void _hit() {
    if (invincible) return;
    if (shieldHitsLeft > 0) {
      shieldHitsLeft--;
      invincibleSeconds =
          Upgrades.shieldGraceSeconds(_level(UpgradeType.shield));
      return;
    }
    phase = RunPhase.crashed;
  }

  /// Continue after a crash (rewarded ad or token). Once per run.
  void revive() {
    if (phase != RunPhase.crashed || reviveUsed) return;
    reviveUsed = true;
    final px = probeWorldX;
    gates.removeWhere((g) =>
        g.x + Tuning.gateWidth > px - Tuning.probeRadius - Tuning.gateWidth &&
        g.x < px + Tuning.reviveClearAhead);
    probeY = Tuning.worldHeight / 2;
    velocityY = Tuning.thrustVelocity / 2;
    invincibleSeconds = Tuning.reviveInvincibleSeconds;
    _accumulator = 0;
    phase = RunPhase.playing;
  }

  /// End the run (player declined or couldn't revive).
  RunResult finish() {
    phase = RunPhase.over;
    final multiplier =
        Upgrades.crystalMultiplier(_level(UpgradeType.crystalValue));
    return RunResult(
      distanceMeters: distanceMeters.floor(),
      rawCrystals: rawCrystals,
      earnedCrystals: (rawCrystals * multiplier).floor(),
      nearMisses: nearMisses,
      revived: reviveUsed,
    );
  }

  static bool _circleHitsRect(double cx, double cy, double r, double rx,
      double ry, double rw, double rh) {
    if (rh <= 0) return false;
    final nearestX = cx.clamp(rx, rx + rw);
    final nearestY = cy.clamp(ry, ry + rh);
    final dx = cx - nearestX;
    final dy = cy - nearestY;
    return dx * dx + dy * dy < r * r;
  }
}
