import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../logic/run_session.dart';
import '../logic/tuning.dart';
import '../logic/upgrades.dart';

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
    _session = RunSession(worldWidth: _worldWidth, upgradeLevels: upgradeLevels);
    _stars = List.generate(
      70,
      (_) => _Star(rnd.nextDouble(), rnd.nextDouble() * Tuning.worldHeight,
          0.1 + rnd.nextDouble() * 0.5),
    );
    _particles.clear();
    _shakeLeft = 0;
    _flashLeft = 0;
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
    if (phase.value == p) return;
    if (p == RunPhase.crashed) _onCrash();
    phase.value = p;
  }

  void _onCrash() {
    final s = _session;
    if (s == null) return;
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
    _session?.update(dt);
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
      final x = (star.x * w - s.scroll * star.depth) % w;
      paint.color = Color.fromRGBO(255, 255, 255, 0.25 + star.depth);
      canvas.drawCircle(Offset(x, star.y), 0.25 + star.depth * 0.5, paint);
    }
  }

  void _drawBestMarker(Canvas canvas, RunSession s) {
    if (bestDistance <= 0) return;
    final x = bestDistance / Tuning.metersPerUnit - s.scroll + s.probeX;
    if (x < 0 || x > _worldWidth) return;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, Tuning.worldHeight),
      Paint()
        ..color = const Color(0x88FFD54F)
        ..strokeWidth = 0.6,
    );
  }

  void _drawGate(Canvas canvas, RunSession s, Gate g) {
    final x = g.x - s.scroll;
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
    final c = Offset(p.x - s.scroll, p.y);
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
    final c = Offset(s.probeX, s.probeY);
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
      final c = Offset(p.x - s.scroll, p.y);
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
    _text(canvas, '${s.distanceMeters.floor()} m', Offset(left, top),
        size.y * 0.04, const Color(0xFFFFFFFF));
    _text(canvas, '◆ ${s.rawCrystals}', Offset(left, top + size.y * 0.05),
        size.y * 0.03, const Color(0xFF4DD0E1));
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
