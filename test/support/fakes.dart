import 'dart:async';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/app/game_controller.dart';
import 'package:probe_dash/game/probe_game.dart';
import 'package:probe_dash/logic/progress.dart';
import 'package:probe_dash/logic/tuning.dart';
import 'package:probe_dash/services/ad_service.dart';
import 'package:probe_dash/services/save_store.dart';

/// An [AdService] that never touches the ads plugin. Rewarded ads are
/// "ready" when [ready] is true and always complete with [watchResult].
class FakeAds extends AdService {
  FakeAds({this.ready = true, this.watchResult = false})
      : super(enabled: false);

  bool ready;
  bool watchResult;
  int rewardedShown = 0;

  @override
  bool get rewardedReady => ready;

  @override
  Future<bool> showRewarded() async {
    if (!ready) return false;
    rewardedShown++;
    return watchResult;
  }
}

/// A [SaveStore] whose saves finish only when the test says so.
class SlowStore extends SaveStore {
  SlowStore([super.dir]);

  final List<Completer<void>> pending = [];
  int saves = 0;

  @override
  Future<void> save(Progress progress) {
    saves++;
    final c = Completer<void>();
    pending.add(c);
    return c.future;
  }
}

/// A [SaveStore] that records saves and finishes them at once, so widget
/// tests (which run on a fake clock) never wait on real file IO.
class InstantStore extends SaveStore {
  InstantStore() : super(Directory.systemTemp);

  int saves = 0;

  @override
  Future<void> save(Progress progress) {
    saves++;
    return Future.value();
  }
}

GameController makeController({
  int crystals = 0,
  int best = 0,
  AdService? ads,
  SaveStore? store,
}) =>
    GameController(
      progress: Progress(crystals: crystals, bestDistance: best),
      store: store ?? InstantStore(),
      ads: ads ?? AdService(enabled: false),
    );

ProbeGame gameOf(WidgetTester tester) =>
    tester.widget<GameWidget<ProbeGame>>(find.byType(GameWidget<ProbeGame>))
        .game!;

/// Starts a run and drops the probe onto the deadly floor.
Future<void> crashNow(WidgetTester tester) async {
  final g = gameOf(tester);
  final s = g.session!;
  if (s.phase.name == 'ready') g.tapInput();
  s.probeY = Tuning.worldHeight;
  s.velocityY = Tuning.maxFallSpeed;
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

/// `pumpAndSettle` never settles while Flame's game loop runs, so route
/// transitions are pumped for a fixed time instead.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Waits out the 500 ms crash beat and the overlay's 400 ms input lock, so
/// the revive or results panel is on screen and accepts taps.
Future<void> waitForOverlay(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600)); // beat ends
  await tester.pump(const Duration(milliseconds: 500)); // lock ends
}
