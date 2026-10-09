import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/game_controller.dart';
import '../game/probe_game.dart';
import '../logic/run_session.dart';
import '../logic/upgrades.dart';
import '../services/ad_service.dart';
import 'upgrades_screen.dart';

/// One play session: the game plus revive and results overlays.
/// "Play again" starts a new run without leaving the screen (GAME-4).
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// Crash beat (FEEL-01, A-01): the crash plays out on screen for this long
  /// before any overlay appears.
  static const crashBeat = Duration(milliseconds: 500);

  late ProbeGame _game;
  RunResult? _result;
  bool _newBest = false;
  bool _doubled = false;
  bool _busy = false;

  /// Set when the current run has been finished and applied; a run is
  /// applied to progress at most once (A-20 / UX-21).
  bool _finished = false;

  /// Runs during the crash beat; when it fires the revive offer or the
  /// results appear.
  Timer? _beatTimer;
  bool _offerRevive = false;

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    // Full screen while playing: no status bar over the HUD and no gesture
    // handle over the deadly floor (FEEL-11, A-06). Swiping from an edge
    // shows the bars briefly.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _game = _makeGame();
  }

  ProbeGame _makeGame() {
    final g = ProbeGame(
      upgradeLevels: Map.of(c.progress.upgrades),
      bestDistance: c.progress.bestDistance,
    );
    g.phase.addListener(_onPhase);
    return g;
  }

  void _onPhase() {
    if (!mounted) return;
    if (_game.phase.value == RunPhase.crashed &&
        !_finished &&
        _beatTimer == null) {
      _beatTimer = Timer(crashBeat, _afterCrashBeat);
    }
    setState(() {});
  }

  void _afterCrashBeat() {
    _beatTimer = null;
    if (!mounted || _finished) return;
    final s = _game.session;
    // No revive available (already used, or no rewarded ad loaded): go
    // straight to results (spec §7 "Crashed --> Results"; A-08), instead of
    // a 5 s wait in front of a disabled button.
    if (s == null || !s.canRevive || !c.ads.rewardedReady) {
      _finish();
      return;
    }
    setState(() => _offerRevive = true);
  }

  void _finish() {
    // Two paths can land here for one run (double tap on "No thanks", or the
    // countdown ending as the player taps). Only the first one counts.
    if (_finished) return;
    _finished = true;
    _beatTimer?.cancel();
    _beatTimer = null;
    final result = _game.finish();
    if (result == null) return;
    final best = c.completeRun(result); // save stays queued, not awaited
    if (!mounted) return;
    setState(() {
      _result = result;
      _newBest = best;
      _doubled = false;
    });
  }

  Future<void> _watchReviveAd() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await c.ads.showRewarded();
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == RewardedOutcome.earned) {
      _offerRevive = false;
      _game.revive();
    } else {
      _finish();
    }
  }

  Future<void> _watchDoubleAd() async {
    final r = _result;
    if (r == null || _busy || _doubled) return;
    setState(() => _busy = true);
    final ok = await c.doubleCrystals(r);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _doubled = ok;
    });
  }

  Future<void> _leaveResults({required bool playAgain}) async {
    if (_busy) return;
    setState(() => _busy = true);
    await c.maybeShowInterstitial();
    if (!mounted) return;
    if (!playAgain) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _result = null;
      _finished = false;
      _offerRevive = false;
    });
    // Same game, same GameWidget: just a new run with any new upgrade
    // levels and the new best (GAME-4, FEEL-13).
    _game.newRun(
      upgradeLevels: c.progress.upgrades,
      bestDistance: c.progress.bestDistance,
    );
  }

  Future<void> _openUpgrades() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => UpgradesScreen(controller: c)));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _beatTimer?.cancel();
    _game.phase.removeListener(_onPhase);
    super.dispose();
  }

  /// Android back / back swipe mid-run (FEEL-03, A-07): instead of closing
  /// the screen and losing the run, end it through the normal finish path
  /// so its crystals are saved and the results show. No pause state here
  /// (owner decision D1 pending).
  void _onBack(bool didPop, Object? _) {
    if (didPop || _busy) return; // an ad is on screen: ignore
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _game.phase.value;
    return PopScope(
      canPop: phase == RunPhase.ready || _result != null,
      onPopInvokedWithResult: _onBack,
      child: _buildBody(phase),
    );
  }

  Widget _buildBody(RunPhase phase) {
    _game.viewPadding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF070B1A),
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _game.tapInput(),
              child: GameWidget(key: ObjectKey(_game), game: _game),
            ),
          ),
          if (phase == RunPhase.crashed && _offerRevive && _result == null)
            _EntryGuard(
              key: const ValueKey('revive'),
              child: _ReviveOverlay(
                adReady: c.ads.rewardedReadyListenable,
                busy: _busy,
                onWatch: _watchReviveAd,
                onDecline: _finish,
              ),
            ),
          if (_result != null)
            _EntryGuard(
              key: const ValueKey('results'),
              child: _ResultsOverlay(
                result: _result!,
                newBest: _newBest,
                best: c.progress.bestDistance,
                totalCrystals: c.progress.crystals,
                upgradeOffer: Upgrades.cheapestAffordable(
                    c.progress.upgrades, c.progress.crystals),
                adReady: c.ads.rewardedReadyListenable,
                doubled: _doubled,
                busy: _busy,
                onDouble: _watchDoubleAd,
                onPlayAgain: () => _leaveResults(playAgain: true),
                onUpgrades: _openUpgrades,
                onHome: () => _leaveResults(playAgain: false),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fades an overlay in and ignores taps for its first [lock] (FEEL-01,
/// A-01), so taps the player was already making at the crash can't start
/// an ad, decline a revive, or skip the results by accident.
class _EntryGuard extends StatefulWidget {
  const _EntryGuard({super.key, required this.child});

  static const lock = Duration(milliseconds: 400);
  static const fadeIn = Duration(milliseconds: 250);

  final Widget child;

  @override
  State<_EntryGuard> createState() => _EntryGuardState();
}

class _EntryGuardState extends State<_EntryGuard> {
  bool _armed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_EntryGuard.lock, () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_armed,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: _EntryGuard.fadeIn,
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: widget.child,
      ),
    );
  }
}

class _ReviveOverlay extends StatefulWidget {
  const _ReviveOverlay({
    required this.adReady,
    required this.busy,
    required this.onWatch,
    required this.onDecline,
  });

  final ValueListenable<bool> adReady;
  final bool busy;
  final VoidCallback onWatch;
  final VoidCallback onDecline;

  @override
  State<_ReviveOverlay> createState() => _ReviveOverlayState();
}

class _ReviveOverlayState extends State<_ReviveOverlay> {
  static const _seconds = 5;
  int _left = _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (widget.busy) return; // pause while the ad is open
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        widget.onDecline();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(children: [
      const Text('CONTINUE?',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('$_left', style: const TextStyle(fontSize: 40)),
      const SizedBox(height: 16),
      ValueListenableBuilder<bool>(
        valueListenable: widget.adReady,
        builder: (context, ready, _) => FilledButton.icon(
          onPressed: ready && !widget.busy ? widget.onWatch : null,
          icon: const Icon(Icons.play_circle),
          label: Text(ready ? 'Watch ad to revive' : 'No ad available'),
        ),
      ),
      TextButton(
        onPressed: widget.busy ? null : widget.onDecline,
        child: const Text('No thanks'),
      ),
    ]);
  }
}

class _ResultsOverlay extends StatelessWidget {
  const _ResultsOverlay({
    required this.result,
    required this.newBest,
    required this.best,
    required this.totalCrystals,
    required this.upgradeOffer,
    required this.adReady,
    required this.doubled,
    required this.busy,
    required this.onDouble,
    required this.onPlayAgain,
    required this.onUpgrades,
    required this.onHome,
  });

  final RunResult result;
  final bool newBest;
  final int best;
  final int totalCrystals;
  final UpgradeOffer? upgradeOffer;
  final ValueListenable<bool> adReady;
  final bool doubled;
  final bool busy;
  final VoidCallback onDouble;
  final VoidCallback onPlayAgain;
  final VoidCallback onUpgrades;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final earned = result.earnedCrystals * (doubled ? 2 : 1);
    return _Panel(children: [
      if (newBest)
        const Text('NEW BEST!',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFD54F))),
      Text('${result.distanceMeters} m',
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
      Text('Best: $best m', style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 12),
      Text('+$earned ◆',
          style: const TextStyle(fontSize: 26, color: Color(0xFF4DD0E1))),
      if (result.nearMisses > 0)
        Text('${result.nearMisses} near misses',
            style: const TextStyle(color: Colors.white70)),
      Text('Total: $totalCrystals ◆',
          style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 12),
      if (!doubled && earned > 0)
        ValueListenableBuilder<bool>(
          valueListenable: adReady,
          builder: (context, ready, _) => OutlinedButton.icon(
            onPressed: ready && !busy ? onDouble : null,
            icon: const Icon(Icons.play_circle),
            label: Text(ready ? 'Watch ad: 2× crystals' : 'No ad available'),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: busy ? null : onPlayAgain,
        style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
        child: const Text('PLAY AGAIN', style: TextStyle(fontSize: 18)),
      ),
      if (upgradeOffer case final offer?) ...[
        const SizedBox(height: 8),
        // One line on every phone: the short label fits 360 dp at normal
        // font size, and scales down instead of wrapping when it doesn't.
        OutlinedButton.icon(
          onPressed: busy ? null : onUpgrades,
          icon: const Icon(Icons.upgrade),
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(offer.label, maxLines: 1, softWrap: false),
          ),
        ),
      ],
      // Wraps onto two lines at large font sizes instead of overflowing.
      Wrap(alignment: WrapAlignment.center, children: [
        TextButton(onPressed: busy ? null : onUpgrades, child: const Text('Upgrades')),
        TextButton(onPressed: busy ? null : onHome, child: const Text('Home')),
      ]),
    ]);
  }
}

/// The revive and results card. Font-scale safe (A-27): text is clamped to
/// 1.3× and the card scrolls when it is taller than the screen, so no button
/// ends up outside the card where it would be drawn but not tappable.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  static const double maxTextScale = 1.3;
  static const double maxWidth = 420;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xAA000000),
      alignment: Alignment.center,
      child: SafeArea(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: maxTextScale,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151B33),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                      mainAxisSize: MainAxisSize.min, children: children),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
