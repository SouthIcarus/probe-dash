import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app/game_controller.dart';
import '../game/probe_game.dart';
import '../logic/run_session.dart';
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
  late ProbeGame _game;
  RunResult? _result;
  bool _newBest = false;
  bool _doubled = false;
  bool _busy = false;

  /// Set when the current run has been finished and applied; a run is
  /// applied to progress at most once (A-20 / UX-21).
  bool _finished = false;

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
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
    if (_game.phase.value == RunPhase.crashed) {
      final s = _game.session;
      // No revive left: go straight to results.
      if (s == null || !s.canRevive) {
        _finish();
        return;
      }
    }
    setState(() {});
  }

  Future<void> _finish() async {
    // Two paths can land here for one run (double tap on "No thanks", or the
    // countdown ending as the player taps). Only the first one counts.
    if (_finished) return;
    _finished = true;
    final result = _game.finish();
    if (result == null) return;
    final best = await c.completeRun(result);
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
    final watched = await c.ads.showRewarded();
    if (!mounted) return;
    setState(() => _busy = false);
    if (watched) {
      _game.revive();
    } else {
      await _finish();
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
    _game.phase.removeListener(_onPhase);
    setState(() {
      _busy = false;
      _result = null;
      _finished = false;
      _game = _makeGame(); // picks up any new upgrade levels
    });
  }

  Future<void> _openUpgrades() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => UpgradesScreen(controller: c)));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _game.phase.removeListener(_onPhase);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _game.phase.value;
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
          if (phase == RunPhase.crashed && _result == null)
            _ReviveOverlay(
              adReady: c.ads.rewardedReady,
              busy: _busy,
              onWatch: _watchReviveAd,
              onDecline: _finish,
            ),
          if (_result != null)
            _ResultsOverlay(
              result: _result!,
              newBest: _newBest,
              best: c.progress.bestDistance,
              totalCrystals: c.progress.crystals,
              canDouble: !_doubled && c.ads.rewardedReady,
              doubled: _doubled,
              busy: _busy,
              onDouble: _watchDoubleAd,
              onPlayAgain: () => _leaveResults(playAgain: true),
              onUpgrades: _openUpgrades,
              onHome: () => _leaveResults(playAgain: false),
            ),
        ],
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

  final bool adReady;
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
      FilledButton.icon(
        onPressed: widget.adReady && !widget.busy ? widget.onWatch : null,
        icon: const Icon(Icons.play_circle),
        label: Text(widget.adReady ? 'Watch ad to revive' : 'No ad available'),
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
    required this.canDouble,
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
  final bool canDouble;
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
        OutlinedButton.icon(
          onPressed: canDouble && !busy ? onDouble : null,
          icon: const Icon(Icons.play_circle),
          label: Text(canDouble ? 'Watch ad: 2× crystals' : 'No ad available'),
        ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: busy ? null : onPlayAgain,
        style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
        child: const Text('PLAY AGAIN', style: TextStyle(fontSize: 18)),
      ),
      Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(onPressed: busy ? null : onUpgrades, child: const Text('Upgrades')),
        TextButton(onPressed: busy ? null : onHome, child: const Text('Home')),
      ]),
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xAA000000),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF151B33),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
