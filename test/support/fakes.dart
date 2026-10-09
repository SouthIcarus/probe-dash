import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/app/game_controller.dart';
import 'package:probe_dash/game/haptics.dart';
import 'package:probe_dash/game/probe_game.dart';
import 'package:probe_dash/logic/progress.dart';
import 'package:probe_dash/logic/tuning.dart';
import 'package:probe_dash/services/ad_service.dart';
import 'package:probe_dash/services/save_store.dart';

/// An [AdService] that never touches the ads plugin. Rewarded ads are
/// "ready" when [ready] is true and always end with [rewardedOutcome]
/// (`watchResult: true` is shorthand for [RewardedOutcome.earned]; the
/// default is a player who closes the ad early).
class FakeAds extends AdService {
  FakeAds({
    bool ready = true,
    bool watchResult = false,
    RewardedOutcome? rewardedOutcome,
  })  : _ready = ValueNotifier(ready),
        rewardedOutcome = rewardedOutcome ??
            (watchResult ? RewardedOutcome.earned : RewardedOutcome.closedEarly),
        super(enabled: false);

  final ValueNotifier<bool> _ready;
  RewardedOutcome rewardedOutcome;
  int rewardedShown = 0;

  set watchResult(bool v) => rewardedOutcome =
      v ? RewardedOutcome.earned : RewardedOutcome.closedEarly;

  bool get ready => _ready.value;
  set ready(bool v) => _ready.value = v; // like an ad finishing loading

  @override
  ValueListenable<bool> get rewardedReadyListenable => _ready;

  @override
  Future<RewardedOutcome> showRewarded() async {
    if (!ready) return RewardedOutcome.notLoaded;
    rewardedShown++;
    return rewardedOutcome;
  }

  // ---- Interstitial ----

  /// Age of the loaded interstitial; null = none loaded (the default, like
  /// a real service with ads disabled).
  Duration? loadedInterstitialAge;

  @override
  Duration? get interstitialAge => loadedInterstitialAge;

  /// What the next shown interstitial does (timers run on the test clock).
  InterstitialScript interstitialScript = const InterstitialScript();

  /// Shared with [InstantStore.log] to check the order of saves and shows.
  List<String>? log;

  int interstitialShowCalls = 0;
  int interstitialLoadRequests = 0;
  int staleInterstitialsDiscarded = 0;

  /// Whether the scripted ad is on screen now.
  bool interstitialOnScreen = false;

  VoidCallback? _onShown, _onFailed, _onDismissed;
  final List<Timer> _timers = [];

  @override
  void requestInterstitialLoad() => interstitialLoadRequests++;

  @override
  void discardStaleInterstitial() {
    staleInterstitialsDiscarded++;
    loadedInterstitialAge = null;
    interstitialLoadRequests++;
  }

  /// Like a load finishing later (AD-7): the ad is now loaded.
  void finishInterstitialLoad() => loadedInterstitialAge = Duration.zero;

  @override
  bool showInterstitial({
    required VoidCallback onShown,
    required VoidCallback onFailed,
    required VoidCallback onDismissed,
  }) {
    if (loadedInterstitialAge == null) return false;
    interstitialShowCalls++;
    log?.add('show');
    loadedInterstitialAge = null; // consumed, like the real service
    _onShown = onShown;
    _onFailed = onFailed;
    _onDismissed = onDismissed;
    final script = interstitialScript;
    final at = script.appearsAfter;
    if (at != null) {
      _timers.add(Timer(at, () {
        if (script.fails) {
          failInterstitial();
          return;
        }
        appearInterstitial();
        final close = script.dismissAfter;
        if (close != null) _timers.add(Timer(close, dismissInterstitial));
      }));
    }
    return true;
  }

  /// The SDK's `onAdShowedFullScreenContent`.
  void appearInterstitial() {
    interstitialOnScreen = true;
    log?.add('appear');
    _onShown?.call();
  }

  /// `onAdDismissedFullScreenContent` (close button or back inside the ad).
  void dismissInterstitial() {
    interstitialOnScreen = false;
    log?.add('dismiss');
    final cb = _onDismissed;
    _clear();
    interstitialLoadRequests++; // the real service loads the next one
    cb?.call();
  }

  /// `onAdFailedToShowFullScreenContent`.
  void failInterstitial() {
    interstitialOnScreen = false;
    log?.add('fail');
    final cb = _onFailed;
    _clear();
    interstitialLoadRequests++;
    cb?.call();
  }

  void _clear() {
    _onShown = _onFailed = _onDismissed = null;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }
}

/// How a [FakeAds] interstitial behaves after `showInterstitial`.
class InterstitialScript {
  const InterstitialScript({
    this.appearsAfter = const Duration(milliseconds: 300),
    this.fails = false,
    this.dismissAfter,
  });

  /// When `onShown` (or `onFailed` if [fails]) fires after the show call;
  /// null = no callback at all (the ad hangs; the test drives it by hand).
  final Duration? appearsAfter;

  /// Fail to show at [appearsAfter] instead of appearing.
  final bool fails;

  /// How long the ad stays up after appearing; null = until the test calls
  /// [FakeAds.dismissInterstitial].
  final Duration? dismissAfter;
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
  InstantStore({this.log}) : super(Directory.systemTemp);

  int saves = 0;

  /// What each save wrote, in order (like the file on disk after it).
  final List<Map<String, Object?>> saved = [];

  /// Shared with [FakeAds.log] to check the order of saves and shows.
  final List<String>? log;

  /// The last save as it would be read back after an app kill.
  Progress get onDisk => Progress.fromJson(saved.last);

  @override
  Future<void> save(Progress progress) {
    saves++;
    saved.add(jsonDecode(jsonEncode(progress.toJson())) as Map<String, Object?>);
    log?.add('save');
    return Future.value();
  }
}

GameController makeController({
  int crystals = 0,
  int best = 0,
  int runs = 0,
  bool removeAds = false,
  DateTime? lastInterstitialAt,
  AdService? ads,
  SaveStore? store,
  DateTime Function()? clock,
}) =>
    GameController(
      progress: Progress(
        crystals: crystals,
        bestDistance: best,
        runs: runs,
        removeAds: removeAds,
        lastInterstitialAt: lastInterstitialAt,
      ),
      store: store ?? InstantStore(),
      ads: ads ?? AdService(enabled: false),
      clock: clock,
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

/// A [HapticsBackend] that records which haptic each event asked for.
class RecordingHaptics implements HapticsBackend {
  final List<HapticKind> played = [];

  @override
  void play(HapticKind kind) => played.add(kind);
}

/// Routes [Haptics] to a fresh recorder for this test and restores the
/// real backend afterwards.
List<HapticKind> recordHaptics() {
  final rec = RecordingHaptics();
  final previous = Haptics.backend;
  Haptics.backend = rec;
  addTearDown(() => Haptics.backend = previous);
  return rec.played;
}
