import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../logic/run_session.dart';
import '../logic/tuning.dart';
import '../logic/upgrades.dart';
import 'haptics.dart';

/// Draws a [RunSession] and drives it with Flame's game loop.
///
/// Prototype art is plain vector shapes; real sprites come later. All game
/// rules live in [RunSession]; this class only renders and forwards taps.
class ProbeGame extends FlameGame {
  ProbeGame({required this.upgradeLevels, required this.bestDistance});

  final Map<UpgradeType, int> upgradeLevels;
  final int bestDistance;

  /// UI listens to this to show the revive and results overlays.
  final ValueNotifier<RunPhase> phase = ValueNotifier(RunPhase.ready);

  /// System insets (status bar, camera cutout) in logical pixels; the
  /// screen passes `MediaQuery.viewPaddingOf` so the HUD stays clear of
  /// them (FEEL-11, A-06).
  EdgeInsets viewPadding = EdgeInsets.zero;

  /// Top of the HUD in logical pixels.
  double get hudTop => hudTopFor(viewPadding.top, size.y);

  /// A-06: `max(height × 0.05, inset + 8 dp)`.
  static double hudTopFor(double insetTop, double height) =>
      math.max(height * 0.05, insetTop + 8);

  /// Deadly floor band (FEEL-09, A-05): from y = 98.5 u to the bottom, red at
  /// 70% with a solid 0.4 u top line. The ceiling is safe and stays undrawn.
  static const double floorBandTop = 98.5;
  static const double floorLineWidth = 0.4;
  static final Paint _floorBand = Paint()..color = const Color(0xB3FF5252);
  static final Paint _floorLine = Paint()..color = const Color(0xFFFF5252);

  RunSession? _session;
  RunSession? get session => _session;

  late List<_Star> _stars;
  double _time = 0;

  /// One shared random source for render-only effects.
  static final math.Random _fx = math.Random();

  // Render-only effects (no effect on the simulation).
  double _shakeLeft = 0; // seconds of shake remaining
  double _shakeDuration = 0;
  double _shakeAmplitude = 0; // world units at the start of the shake
  double _flashLeft = 0; // seconds of white flash remaining
  final List<_Particle> _particles = [];

  /// Crash beat (FEEL-01, A-01): shake 300 ms up to 1.5 u, white flash at
  /// 25% fading over 120 ms, and debris flying out and fading over 500 ms.
  static const double crashShakeSeconds = 0.3;
  static const double crashShakeUnits = 1.5;
  static const double crashFlashSeconds = 0.12;
  static const int crashDebris = 12;

  /// Shield hit (A-00, FEEL-07): a lighter shake and a short hit-stop.
  static const double shieldShakeSeconds = 0.25;
  static const double shieldShakeUnits = 1.0;
  static const double hitStopSeconds = 0.08;

  /// Near-miss pop-up "CLOSE! +2 ◆" (A-03): starts 4 u above the probe,
  /// rises 6 u and fades over 700 ms; at most 2 on screen.
  static const double popupSeconds = 0.7;
  static const int maxPopups = 2;

  /// A-29: at most one near-miss haptic per 300 ms.
  static const double nearMissHapticGap = 0.3;

  /// Best-distance chase (A-04): "NEW BEST!" banner at 30% height; scales
  /// 0.6× → 1.0× over 150 ms, holds 800 ms, fades over 300 ms.
  static const double bannerGrow = 0.15;
  static const double bannerHold = 0.8;
  static const double bannerFade = 0.3;
  static const Color gold = Color(0xFFFFD54F);

  /// Seconds since the "NEW BEST!" banner appeared, or null when hidden.
  double? newBestBannerAge;

  /// Banner scale at [age] seconds.
  static double bannerScale(double age) =>
      age >= bannerGrow ? 1.0 : 0.6 + 0.4 * (age / bannerGrow);

  /// Banner opacity at [age] seconds (0 once it has faded out).
  static double bannerAlpha(double age) {
    const fadeStart = bannerGrow + bannerHold;
    if (age <= fadeStart) return 1;
    return math.max(0, 1 - (age - fadeStart) / bannerFade);
  }

  /// The HUD's best line: "BEST 1287 m" while chasing, "NEW BEST" once
  /// passed, nothing before the player has a best.
  static String? bestLine(int best, {required bool passed}) {
    if (best <= 0) return null;
    return passed ? 'NEW BEST' : 'BEST $best m';
  }

  double _hitStopLeft = 0;
  double _lastNearMissHaptic = -1;
  final List<_Popup> _popups = [];

  double get _scale => size.y / Tuning.worldHeight;
  double get _worldWidth => size.x / _scale;

  @override
  Color backgroundColor() => const Color(0xFF070B1A);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x > 0 && size.y > 0 && _session == null) newRun();
  }

  void newRun() {
    final rnd = math.Random();
    _session = RunSession(
        worldWidth: _worldWidth,
        upgradeLevels: upgradeLevels,
        bestDistance: bestDistance);
    _stars = List.generate(
      70,
      (_) => _Star(rnd.nextDouble(), rnd.nextDouble() * Tuning.worldHeight,
          0.1 + rnd.nextDouble() * 0.5),
    );
    _particles.clear();
    _popups.clear();
    _shakeLeft = 0;
    _flashLeft = 0;
    _hitStopLeft = 0;
    newBestBannerAge = null;
    phase.value = RunPhase.ready;
  }

  void tapInput() => _session?.tap();

  void revive() {
    _session?.revive();
    _syncPhase();
  }

  RunResult? finish() {
    final result = _session?.finish();
    _syncPhase();
    return result;
  }

  void _syncPhase() {
    final p = _session?.phase ?? RunPhase.ready;
    if (phase.value != p) phase.value = p;
  }

  /// Turns the run's events into feedback (A-00, FEEL-07). Render-only:
  /// nothing here changes the simulation.
  void _handleEvents(RunSession s) {
    for (final e in s.drainEvents()) {
      switch (e) {
        case RunEvent.crash:
          Haptics.crash();
          _onCrash(s);
        case RunEvent.shieldHit:
          Haptics.shieldHit();
          _shake(shieldShakeUnits, shieldShakeSeconds);
          _hitStopLeft = hitStopSeconds;
        case RunEvent.nearMiss:
          if (_time - _lastNearMissHaptic >= nearMissHapticGap ||
              _lastNearMissHaptic < 0) {
            _lastNearMissHaptic = _time;
            Haptics.nearMiss();
          }
          if (_popups.length >= maxPopups) _popups.removeAt(0);
          _popups.add(_Popup('CLOSE! +${Tuning.nearMissBonus} ◆', s.probeY));
        case RunEvent.crystal:
          _burst(s.probeWorldX, s.probeY, 4, const [Color(0xFF4DD0E1)],
              minSpeed: 12, maxSpeed: 12, life: 0.25, size: 0.6);
        case RunEvent.newBest:
          newBestBannerAge = 0;
        case RunEvent.magnet:
        case RunEvent.floorBounce:
        case RunEvent.headStartEnd:
          break;
      }
    }
  }

  void _onCrash(RunSession s) {
    _shake(crashShakeUnits, crashShakeSeconds);
    _flashLeft = crashFlashSeconds;
    _burst(s.probeWorldX, s.probeY, crashDebris,
        const [Color(0xFFE3F2FD), Color(0xFFFF9100)],
        minSpeed: 20, maxSpeed: 40, life: 0.5, size: 1.2, triangle: true);
  }

  void _shake(double amplitude, double seconds) {
    // A new shake never weakens one already running.
    if (_shakeLeft > 0 &&
        _shakeAmplitude * _shakeLeft / _shakeDuration >= amplitude) {
      return;
    }
    _shakeAmplitude = amplitude;
    _shakeDuration = seconds;
    _shakeLeft = seconds;
  }

  void _burst(double worldX, double y, int count, List<Color> colors,
      {required double minSpeed,
      required double maxSpeed,
      required double life,
      required double size,
      bool triangle = false}) {
    for (var i = 0; i < count; i++) {
      final angle = _fx.nextDouble() * math.pi * 2;
      final speed = minSpeed + _fx.nextDouble() * (maxSpeed - minSpeed);
      _particles.add(_Particle(
        x: worldX,
        y: y,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        life: life,
        size: size,
        spin: _fx.nextDouble() * math.pi * 2,
        color: colors[i % colors.length],
        triangle: triangle,
      ));
    }
  }

  void _updateEffects(double dt) {
    final banner = newBestBannerAge;
    if (banner != null) {
      final age = banner + dt;
      newBestBannerAge =
          age >= bannerGrow + bannerHold + bannerFade ? null : age;
    }
    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= popupSeconds);
    if (_shakeLeft > 0) _shakeLeft = math.max(0, _shakeLeft - dt);
    if (_flashLeft > 0) _flashLeft = math.max(0, _flashLeft - dt);
    for (final p in _particles) {
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
    _particles.removeWhere((p) => p.age >= p.life);
  }

  Offset get _shakeOffset {
    if (_shakeLeft <= 0) return Offset.zero;
    final a = _shakeAmplitude * _shakeLeft / _shakeDuration; // linear decay
    return Offset(
        (_fx.nextDouble() * 2 - 1) * a, (_fx.nextDouble() * 2 - 1) * a);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    final s = _session;
    if (s != null) {
      if (_hitStopLeft > 0) {
        _hitStopLeft -= dt; // brief freeze on a shield hit; physics paused
      } else {
        s.update(dt);
      }
      _handleEvents(s);
    }
    _syncPhase();
    _updateEffects(dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final s = _session;
    if (s == null) return;

    canvas.save();
    canvas.scale(_scale);
    final shake = _shakeOffset;
    canvas.translate(shake.dx, shake.dy);
    _drawStars(canvas, s);
    _drawBestMarker(canvas, s);
    for (final g in s.gates) {
      _drawGate(canvas, s, g);
    }
    for (final p in s.pickups) {
      if (!p.collected) _drawPickup(canvas, s, p);
    }
    _drawFloor(canvas);
    _drawProbe(canvas, s);
    _drawParticles(canvas, s);
    canvas.restore();

    if (_flashLeft > 0) {
      canvas.drawRect(
          Offset.zero & size.toSize(),
          Paint()
            ..color = Color.fromRGBO(
                255, 255, 255, 0.25 * _flashLeft / crashFlashSeconds));
    }

    _drawHud(canvas, s);
  }

  void _drawStars(Canvas canvas, RunSession s) {
    final paint = Paint();
    final w = _worldWidth;
    for (final star in _stars) {
      final x = (star.x * w - s.renderScroll * star.depth) % w;
      paint.color = Color.fromRGBO(255, 255, 255, 0.25 + star.depth);
      canvas.drawCircle(Offset(x, star.y), 0.25 + star.depth * 0.5, paint);
    }
  }

  void _drawBestMarker(Canvas canvas, RunSession s) {
    if (bestDistance <= 0) return;
    final x = bestDistance / Tuning.metersPerUnit - s.renderScroll + s.probeX;
    if (x < -1 || x > _worldWidth + 1) return;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, Tuning.worldHeight),
      Paint()
        ..color = gold
        ..strokeWidth = 1.0,
    );
  }

  /// "BEST" label at the top of the marker line, drawn in screen space.
  void _drawBestLabel(Canvas canvas, RunSession s) {
    if (bestDistance <= 0) return;
    final x = bestDistance / Tuning.metersPerUnit - s.renderScroll + s.probeX;
    if (x < -10 || x > _worldWidth + 10) return;
    _text(canvas, 'BEST', Offset(x * _scale, viewPadding.top + 4),
        size.y * 0.022, gold,
        center: true);
  }

  void _drawNewBestBanner(Canvas canvas) {
    final age = newBestBannerAge;
    if (age == null) return;
    final scale = bannerScale(age);
    canvas.save();
    canvas.translate(size.x / 2, size.y * 0.3);
    canvas.scale(scale);
    _text(canvas, 'NEW BEST!', Offset.zero, size.y * 0.045,
        gold.withValues(alpha: bannerAlpha(age)),
        center: true);
    canvas.restore();
  }

  void _drawGate(Canvas canvas, RunSession s, Gate g) {
    final x = g.x - s.renderScroll;
    final rock = Paint()..color = const Color(0xFF5D5A6E);
    final edge = Paint()..color = const Color(0xFF8C87A3);
    const w = Tuning.gateWidth;
    final top = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, -5, w, g.gapTop + 5), const Radius.circular(3));
    final bottom = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, g.gapBottom, w, Tuning.worldHeight - g.gapBottom + 5),
        const Radius.circular(3));
    canvas.drawRRect(top, rock);
    canvas.drawRRect(bottom, rock);
    // Lit rims on the gap edges so the opening reads instantly.
    canvas.drawRect(Rect.fromLTWH(x, g.gapTop - 1.2, w, 1.2), edge);
    canvas.drawRect(Rect.fromLTWH(x, g.gapBottom, w, 1.2), edge);
  }

  void _drawPickup(Canvas canvas, RunSession s, Pickup p) {
    final c = Offset(s.renderPickupX(p) - s.renderScroll, s.renderPickupY(p));
    if (p.kind == PickupKind.crystal) {
      const r = Tuning.crystalRadius;
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * 0.7, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r * 0.7, c.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF4DD0E1));
    } else {
      final pulse = 2.6 + math.sin(_time * 6) * 0.4;
      canvas.drawCircle(c, pulse, Paint()..color = const Color(0xFFE040FB));
      canvas.drawCircle(
          c,
          pulse + 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5
            ..color = const Color(0x88E040FB));
    }
  }

  void _drawProbe(Canvas canvas, RunSession s) {
    final c = Offset(s.probeX, s.renderProbeY);
    const r = Tuning.probeRadius;

    // Blink while invincible (revive / shield grace).
    if (s.invincibleSeconds > 0 && (_time * 10).floor().isEven) return;

    if (s.sinceTap < 0.15 || s.inHeadStart) {
      final flame = Path()
        ..moveTo(c.dx - r * 0.9, c.dy - r * 0.5)
        ..lineTo(c.dx - r * (2.2 + math.Random().nextDouble()), c.dy)
        ..lineTo(c.dx - r * 0.9, c.dy + r * 0.5)
        ..close();
      canvas.drawPath(flame, Paint()..color = const Color(0xFFFF9100));
    }

    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE3F2FD));
    canvas.drawCircle(c.translate(r * 0.3, -r * 0.2), r * 0.45,
        Paint()..color = const Color(0xFF1E88E5));

    if (s.shieldHitsLeft > 0) {
      canvas.drawCircle(
          c,
          r + 1.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6
            ..color = const Color(0xAA64FFDA));
    }
    if (s.magnetSeconds > 0) {
      canvas.drawCircle(
          c,
          Tuning.magnetRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.3
            ..color = const Color(0x44E040FB));
    }
  }

  void _drawFloor(Canvas canvas) {
    final w = _worldWidth + 4; // covers the shake offset at both sides
    canvas.drawRect(
        Rect.fromLTWH(
            -2, floorBandTop, w, Tuning.worldHeight + 2 - floorBandTop),
        _floorBand);
    canvas.drawRect(
        Rect.fromLTWH(-2, floorBandTop, w, floorLineWidth), _floorLine);
  }

  void _drawParticles(Canvas canvas, RunSession s) {
    final paint = Paint();
    for (final p in _particles) {
      final fade = 1 - p.age / p.life;
      paint.color = p.color.withValues(alpha: p.color.a * fade);
      final c = Offset(p.x - s.renderScroll, p.y);
      if (p.triangle) {
        final r = p.size * 0.58; // circumradius of a triangle with side p.size
        final path = Path();
        for (var k = 0; k < 3; k++) {
          final a = p.spin + p.age * 8 + k * math.pi * 2 / 3;
          final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
          if (k == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      } else {
        canvas.drawCircle(c, p.size / 2, paint);
      }
    }
  }

  void _drawHud(Canvas canvas, RunSession s) {
    final pad = size.y * 0.02;
    final left = pad + viewPadding.left;
    final top = hudTop;
    _drawBestLabel(canvas, s);
    _text(canvas, '${s.distanceMeters.floor()} m', Offset(left, top),
        size.y * 0.04, const Color(0xFFFFFFFF));
    final best = bestLine(bestDistance, passed: s.passedBest);
    final hasBest = best != null;
    if (hasBest) {
      _text(canvas, best, Offset(left, top + size.y * 0.05), size.y * 0.022,
          gold);
    }
    _text(canvas, '◆ ${s.rawCrystals}',
        Offset(left, top + size.y * (hasBest ? 0.08 : 0.05)), size.y * 0.03,
        const Color(0xFF4DD0E1));
    _drawNewBestBanner(canvas);
    for (final p in _popups) {
      final t = p.age / popupSeconds;
      final y = (p.y - 4 - 6 * t) * _scale;
      _text(canvas, p.text, Offset(s.probeX * _scale, y), size.y * 0.028,
          const Color(0xFFFF9100).withValues(alpha: 1 - t),
          center: true);
    }
    if (s.phase == RunPhase.ready) {
      _text(canvas, 'TAP TO FLY', Offset(size.x / 2, size.y * 0.7),
          size.y * 0.04, const Color(0xFFFFFFFF),
          center: true);
    }
  }

  void _text(Canvas canvas, String text, Offset at, double fontSize,
      Color color,
      {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color, fontSize: fontSize, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at.translate(-tp.width / 2, 0) : at);
  }
}

/// A floating text pop-up anchored above the probe.
class _Popup {
  _Popup(this.text, this.y);
  final String text;
  final double y; // probe y (world units) when it appeared
  double age = 0;
}

/// A render-only particle in world coordinates.
class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.spin,
    required this.color,
    required this.triangle,
  });

  double x;
  double y;
  final double vx;
  final double vy;
  final double life;
  final double size;
  final double spin;
  final Color color;
  final bool triangle;
  double age = 0;
}

class _Star {
  _Star(this.x, this.y, this.depth);
  final double x; // fraction of world width
  final double y;
  final double depth; // parallax speed factor
}
