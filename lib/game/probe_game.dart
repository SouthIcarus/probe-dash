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

  RunSession? _session;
  RunSession? get session => _session;

  late List<_Star> _stars;
  double _time = 0;

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

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    _session?.update(dt);
    _syncPhase();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final s = _session;
    if (s == null) return;

    canvas.save();
    canvas.scale(_scale);
    _drawStars(canvas, s);
    _drawBestMarker(canvas, s);
    for (final g in s.gates) {
      _drawGate(canvas, s, g);
    }
    for (final p in s.pickups) {
      if (!p.collected) _drawPickup(canvas, s, p);
    }
    _drawProbe(canvas, s);
    canvas.restore();

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

  void _drawHud(Canvas canvas, RunSession s) {
    final pad = size.y * 0.02;
    _text(canvas, '${s.distanceMeters.floor()} m', Offset(pad, pad * 2.5),
        size.y * 0.04, const Color(0xFFFFFFFF));
    _text(canvas, '◆ ${s.rawCrystals}', Offset(pad, pad * 2.5 + size.y * 0.05),
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

class _Star {
  _Star(this.x, this.y, this.depth);
  final double x; // fraction of world width
  final double y;
  final double depth; // parallax speed factor
}
