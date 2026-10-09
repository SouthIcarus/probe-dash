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
  ProbeGame({
    required Map<UpgradeType, int> upgradeLevels,
    required this._bestDistance,
  }) : _upgradeLevels = Map.of(upgradeLevels);

  Map<UpgradeType, int> _upgradeLevels;
  int _bestDistance;

  /// Upgrade levels the current run was started with.
  Map<UpgradeType, int> get upgradeLevels => _upgradeLevels;

  /// The player's best distance (meters) when the current run started.
  int get bestDistance => _bestDistance;

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

  // Paints are created once and reused every frame (FEEL-12).
  static final Paint _rock = Paint()..color = const Color(0xFF5D5A6E);
  static final Paint _rim = Paint()..color = const Color(0xFF8C87A3);
  static final Paint _crystal = Paint()..color = const Color(0xFF4DD0E1);
  static final Paint _magnetCore = Paint()..color = const Color(0xFFE040FB);
  static final Paint _magnetRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5
    ..color = const Color(0x88E040FB);
  static final Paint _magnetField = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.3
    ..color = const Color(0x44E040FB);
  static final Paint _bestLine = Paint()
    ..color = gold
    ..strokeWidth = 1.0;
  static final Paint _shieldRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;

  /// Scratch paint for fills whose colour changes per draw.
  final Paint _fill = Paint();
  final Path _path = Path();

  // HUD text painters, laid out again only when their text changes.
  final _HudText _distanceText = _HudText();
  final _HudText _bestText = _HudText();
  final _HudText _crystalText = _HudText();
  final _HudText _bestLabelText = _HudText();
  final _HudText _bannerText = _HudText();
  final _HudText _readyText = _HudText();
  final List<_HudText> _popupTexts = [_HudText(), _HudText()];

  RunSession? _session;
  RunSession? get session => _session;

  late List<_Star> _stars;
  double _time = 0;

  /// One shared random source for render-only effects and the star field.
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

  /// Probe opacity while blinking (FEEL-08, A-11): the "off" half of each
  /// 0.2 s blink draws the probe at 35% instead of hiding it.
  static const double blinkOffOpacity = 0.35;

  static double probeOpacity(double time, {required bool invincible}) =>
      invincible && (time * 10).floor().isEven ? blinkOffOpacity : 1.0;

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

  /// Starts a fresh run in this same game (GAME-4, FEEL-13): "Play again"
  /// reuses the game instead of rebuilding the widget. Pass the player's
  /// current upgrade levels and best distance.
  void newRun({Map<UpgradeType, int>? upgradeLevels, int? bestDistance}) {
    if (upgradeLevels != null) _upgradeLevels = Map.of(upgradeLevels);
    if (bestDistance != null) _bestDistance = bestDistance;
    _session = RunSession(
        worldWidth: _worldWidth,
        upgradeLevels: _upgradeLevels,
        bestDistance: _bestDistance);
    _stars = List.generate(
      70,
      (_) => _Star(_fx.nextDouble(), _fx.nextDouble() * Tuning.worldHeight,
          0.1 + _fx.nextDouble() * 0.5),
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
          Haptics.newBest(); // A-29: medium double pulse
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
      _fill.color = Color.fromRGBO(
          255, 255, 255, 0.25 * _flashLeft / crashFlashSeconds);
      canvas.drawRect(Offset.zero & size.toSize(), _fill);
    }

    _drawHud(canvas, s);
  }

  void _drawStars(Canvas canvas, RunSession s) {
    final paint = _fill;
    final w = _worldWidth;
    for (final star in _stars) {
      final x = (star.x * w - s.renderScroll * star.depth) % w;
      paint.color = Color.fromRGBO(255, 255, 255, 0.25 + star.depth);
      canvas.drawCircle(Offset(x, star.y), 0.25 + star.depth * 0.5, paint);
    }
  }

  /// On-screen x (world units from the left edge) of the gold best line:
  /// it reaches the probe's x exactly when the run's distance equals [best].
  static double bestMarkerX(
          {required int best,
          required double renderScroll,
          required double probeX}) =>
      best / Tuning.metersPerUnit - renderScroll + probeX;

  /// The best line's x for this frame in world units, or null when there is
  /// no best or the line is off screen.
  @visibleForTesting
  double? get bestMarkerWorldX {
    final s = _session;
    if (s == null || bestDistance <= 0) return null;
    final x = bestMarkerX(
        best: bestDistance, renderScroll: s.renderScroll, probeX: s.probeX);
    return x < -1 || x > _worldWidth + 1 ? null : x;
  }

  /// Where the "NEW BEST!" banner is centred, in logical pixels.
  @visibleForTesting
  Offset get newBestBannerAnchor => Offset(size.x / 2, size.y * 0.3);

  void _drawBestMarker(Canvas canvas, RunSession s) {
    final x = bestMarkerWorldX;
    if (x == null) return;
    canvas.drawLine(Offset(x, 0), Offset(x, Tuning.worldHeight), _bestLine);
  }

  /// "BEST" label at the top of the marker line, drawn in screen space.
  void _drawBestLabel(Canvas canvas, RunSession s) {
    if (bestDistance <= 0) return;
    final x = bestMarkerX(
        best: bestDistance, renderScroll: s.renderScroll, probeX: s.probeX);
    if (x < -10 || x > _worldWidth + 10) return;
    _bestLabelText.paint(canvas, 'BEST', Offset(x * _scale, viewPadding.top + 4),
        size.y * 0.022, gold,
        center: true);
  }

  void _drawNewBestBanner(Canvas canvas) {
    final age = newBestBannerAge;
    if (age == null) return;
    final scale = bannerScale(age);
    canvas.save();
    final anchor = newBestBannerAnchor;
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(scale);
    _bannerText.paint(canvas, 'NEW BEST!', Offset.zero, size.y * 0.045, gold,
        center: true, opacity: bannerAlpha(age));
    canvas.restore();
  }

  void _drawGate(Canvas canvas, RunSession s, Gate g) {
    final x = g.x - s.renderScroll;
    final rock = _rock;
    final edge = _rim;
    const w = Tuning.gateWidth;
    // Square corners: the art matches the square hitbox exactly, so there
    // are no "invisible rock" corners (FEEL-05, art only).
    canvas.drawRect(Rect.fromLTWH(x, -5, w, g.gapTop + 5), rock);
    canvas.drawRect(
        Rect.fromLTWH(x, g.gapBottom, w, Tuning.worldHeight - g.gapBottom + 5),
        rock);
    // Lit rims on the gap edges so the opening reads instantly.
    canvas.drawRect(Rect.fromLTWH(x, g.gapTop - 1.2, w, 1.2), edge);
    canvas.drawRect(Rect.fromLTWH(x, g.gapBottom, w, 1.2), edge);
  }

  void _drawPickup(Canvas canvas, RunSession s, Pickup p) {
    final c = Offset(s.renderPickupX(p) - s.renderScroll, s.renderPickupY(p));
    if (p.kind == PickupKind.crystal) {
      const r = Tuning.crystalRadius;
      final path = _path
        ..reset()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * 0.7, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r * 0.7, c.dy)
        ..close();
      canvas.drawPath(path, _crystal);
    } else {
      final pulse = 2.6 + math.sin(_time * 6) * 0.4;
      canvas.drawCircle(c, pulse, _magnetCore);
      canvas.drawCircle(c, pulse + 1, _magnetRing);
    }
  }

  void _drawProbe(Canvas canvas, RunSession s) {
    final c = Offset(s.probeX, s.renderProbeY);
    const r = Tuning.probeRadius;

    // Blink while invincible (revive / shield grace), but stay visible.
    final o = probeOpacity(_time, invincible: s.invincibleSeconds > 0);
    Color fade(Color color) =>
        o == 1 ? color : color.withValues(alpha: color.a * o);

    if (s.sinceTap < 0.15 || s.inHeadStart) {
      final flame = _path
        ..reset()
        ..moveTo(c.dx - r * 0.9, c.dy - r * 0.5)
        ..lineTo(c.dx - r * (2.2 + _fx.nextDouble()), c.dy)
        ..lineTo(c.dx - r * 0.9, c.dy + r * 0.5)
        ..close();
      canvas.drawPath(flame, _fill..color = fade(const Color(0xFFFF9100)));
    }

    canvas.drawCircle(c, r, _fill..color = fade(const Color(0xFFE3F2FD)));
    canvas.drawCircle(c.translate(r * 0.3, -r * 0.2), r * 0.45,
        _fill..color = fade(const Color(0xFF1E88E5)));

    if (s.shieldHitsLeft > 0) {
      canvas.drawCircle(
          c, r + 1.4, _shieldRing..color = fade(const Color(0xAA64FFDA)));
    }
    if (s.magnetSeconds > 0) {
      canvas.drawCircle(c, Tuning.magnetRadius, _magnetField);
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
    final paint = _fill;
    for (final p in _particles) {
      final fade = 1 - p.age / p.life;
      paint.color = p.color.withValues(alpha: p.color.a * fade);
      final c = Offset(p.x - s.renderScroll, p.y);
      if (p.triangle) {
        final r = p.size * 0.58; // circumradius of a triangle with side p.size
        final path = _path..reset();
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
    _distanceText.paint(canvas, '${s.distanceMeters.floor()} m',
        Offset(left, top), size.y * 0.04, const Color(0xFFFFFFFF));
    final best = bestLine(_bestDistance, passed: s.passedBest);
    final hasBest = best != null;
    if (hasBest) {
      _bestText.paint(canvas, best, Offset(left, top + size.y * 0.05),
          size.y * 0.022, gold);
    }
    _crystalText.paint(canvas, '◆ ${s.rawCrystals}',
        Offset(left, top + size.y * (hasBest ? 0.08 : 0.05)), size.y * 0.03,
        const Color(0xFF4DD0E1));
    _drawNewBestBanner(canvas);
    for (var i = 0; i < _popups.length; i++) {
      final p = _popups[i];
      final t = p.age / popupSeconds;
      final y = (p.y - 4 - 6 * t) * _scale;
      _popupTexts[i].paint(canvas, p.text, Offset(s.probeX * _scale, y),
          size.y * 0.028, const Color(0xFFFF9100),
          center: true, opacity: 1 - t);
    }
    if (s.phase == RunPhase.ready) {
      _readyText.paint(canvas, 'TAP TO FLY', Offset(size.x / 2, size.y * 0.7),
          size.y * 0.04, const Color(0xFFFFFFFF),
          center: true);
    }
  }

  /// How many times HUD text has been laid out (FEEL-12 check).
  @visibleForTesting
  int get hudTextLayouts => [
        _distanceText,
        _bestText,
        _crystalText,
        _bestLabelText,
        _bannerText,
        _readyText,
        ..._popupTexts,
      ].fold(0, (n, t) => n + t.layouts);

  @override
  void onDispose() {
    for (final t in [
      _distanceText,
      _bestText,
      _crystalText,
      _bestLabelText,
      _bannerText,
      _readyText,
      ..._popupTexts,
    ]) {
      t.dispose();
    }
    super.onDispose();
  }
}

/// A HUD text painter that lays its text out again only when the text, size
/// or colour changes (FEEL-12). Digits use tabular figures so numbers don't
/// jitter sideways as they count.
class _HudText {
  final TextPainter _tp = TextPainter(textDirection: TextDirection.ltr);
  String? _text;
  double _fontSize = -1;
  Color? _color;

  /// Debug count of layouts, for tests and profiling.
  int layouts = 0;

  void paint(Canvas canvas, String text, Offset at, double fontSize,
      Color color,
      {bool center = false, double opacity = 1}) {
    if (text != _text || fontSize != _fontSize || color != _color) {
      _text = text;
      _fontSize = fontSize;
      _color = color;
      _tp.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      _tp.layout();
      layouts++;
    }
    final o = center ? at.translate(-_tp.width / 2, 0) : at;
    if (opacity >= 1) {
      _tp.paint(canvas, o);
      return;
    }
    if (opacity <= 0) return;
    // Fade without a new layout: paint through a translucent layer.
    canvas.saveLayer(o & _tp.size,
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    _tp.paint(canvas, o);
    canvas.restore();
  }

  void dispose() => _tp.dispose();
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
