// Probe Test Kit, layer A: runs one scenario on flutter_test with the real
// screens, the real game and the fakes from test/support/fakes.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/app/game_controller.dart';
import 'package:probe_dash/game/probe_game.dart';
import 'package:probe_dash/logic/progress.dart';
import 'package:probe_dash/testkit/fault.dart';
import 'package:probe_dash/ui/home_screen.dart';

import '../../support/fakes.dart';
import 'checks.dart';
import 'scenario.dart';
import 'sha256.dart';

/// One frame of the game's fake clock.
const Duration frame = Duration(milliseconds: 16);

/// What one run of a scenario produced.
class RunOutcome {
  RunOutcome({
    required this.ok,
    required this.failure,
    required this.assertionsChecked,
    required this.gameClockMs,
    required this.traceSha256,
    required this.shots,
    required this.steps,
  });

  final bool ok;
  final String? failure;
  final int assertionsChecked;
  final int gameClockMs;
  final String traceSha256;
  final List<String> shots;

  /// Per step: index, op, ok, message, state (written to `state/ID.json`).
  final List<Map<String, Object?>> steps;
}

/// A step that did not hold; ends the scenario.
class StepFailure implements Exception {
  StepFailure(this.message);
  final String message;
}

/// True once [loadPictureFonts] found the fonts.
bool fontsLoaded = false;

/// Loads Roboto and the Material icon font from the Flutter SDK, so pictures
/// show real letters instead of the solid boxes `flutter_test` draws.
/// Returns what happened, for the report header.
Future<String> loadPictureFonts() async {
  String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || !Directory('$root/bin/cache').existsSync()) {
    // .../bin/cache/artifacts/engine/<platform>/flutter_tester
    var d = File(Platform.resolvedExecutable).parent;
    root = null;
    for (var i = 0; i < 8; i++) {
      if (Directory('${d.path}/bin/cache').existsSync()) {
        root = d.path;
        break;
      }
      d = d.parent;
    }
  }
  final dir = root == null
      ? null
      : Directory('$root/bin/cache/artifacts/material_fonts');
  if (dir == null || !dir.existsSync()) {
    return 'not loaded (SDK font folder not found; pictures show boxes)';
  }
  Future<ByteData> bytes(String name) async {
    final b = await File('${dir.path}/$name').readAsBytes();
    return ByteData.sublistView(b);
  }

  for (final family in ['Roboto']) {
    final roboto = FontLoader(family);
    for (final f in [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
      'roboto-light.ttf',
    ]) {
      roboto.addFont(bytes(f));
    }
    await roboto.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('materialicons-regular.otf'));
  await icons.load();
  fontsLoaded = true;
  return 'Roboto';
}

/// Runs [s] once. [fault] switches on the canary fault. Pictures and the
/// per-step states are collected; nothing is written except pictures, under
/// [shotsDir].
Future<RunOutcome> runScenario(
  WidgetTester tester,
  Scenario s, {
  required Directory kitDir,
  required Directory shotsDir,
  bool fault = false,
}) async {
  final boundaryKey = GlobalKey();
  final trace = StringBuffer();
  final steps = <Map<String, Object?>>[];
  final shots = <String>[];
  var clockMs = 0;
  var checked = 0;
  var profile = s.profile;

  void applyProfile() {
    tester.view.physicalSize =
        Size(profile.width * profile.dpr, profile.height * profile.dpr);
    tester.view.devicePixelRatio = profile.dpr;
    tester.view.viewPadding = FakeViewPadding(top: profile.topInsetPx);
    tester.view.padding = FakeViewPadding(top: profile.topInsetPx);
    tester.platformDispatcher.textScaleFactorTestValue = profile.fontScale;
  }

  // A fresh start: drop any earlier tree, then build the app.
  await tester.pumpWidget(const SizedBox());
  ProbeGame.testSeed = s.profile.seed;
  if (fontsLoaded) ProbeGame.hudFontFamily = 'Roboto';
  TestkitFault.countRunsTwice = fault;
  applyProfile();

  final save = _loadSave(s.setup, kitDir);
  final ads = FakeAds(
      ready: s.setup.rewardedReady, watchResult: s.setup.rewardedWatchResult);
  if (s.setup.interstitialLoaded) {
    ads.loadedInterstitialAge = Duration.zero;
    ads.interstitialScript = const InterstitialScript(
        dismissAfter: Duration(milliseconds: 500));
  }
  final controller = GameController(
    progress: save,
    store: InstantStore(),
    ads: ads,
    clock: () => DateTime.utc(2026, 1, 1, 12),
  );
  await tester.pumpWidget(RepaintBoundary(
    key: boundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF1E88E5),
        useMaterial3: true,
      ),
      home: HomeScreen(controller: controller),
    ),
  ));
  await tester.pump();
  await tester.pump(frame);
  clockMs += 16;

  Map<String, Object?> state() => _buildState(tester, controller, clockMs);

  Future<void> pumpFrames(int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left >= 16 ? 16 : left;
      await tester.pump(Duration(milliseconds: step));
      left -= step;
      clockMs += step;
    }
  }

  Future<String> shot(String name, {String? prefix}) async {
    final file = File('${shotsDir.path}/${prefix ?? s.id}-$name.png');
    await tester.runAsync(() async {
      shotsDir.createSync(recursive: true);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    return 'shots/${file.uri.pathSegments.last}';
  }

  String? failure;
  for (final step in s.steps) {
    final a = step.args;
    var message = 'ok';
    try {
      switch (step.op) {
        case 'tap':
          final text = a['text']! as String;
          final any = find.text(text);
          if (any.evaluate().isEmpty) {
            throw StepFailure('tap "$text": no such text on screen. '
                'Screen: ${_screenName(tester)}, overlay: '
                '${_overlay(tester)}.');
          }
          final hit = any.hitTestable();
          if (hit.evaluate().isEmpty) {
            throw StepFailure('tap "$text": the text is on screen but '
                'covered or not accepting taps yet (input lock or overlay).');
          }
          // `times` taps land inside one frame, before the screen rebuilds.
          for (var i = 0; i < ((a['times'] as int?) ?? 1); i++) {
            await tester.tap(hit.first);
          }
          await pumpFrames(16);
        case 'tap_at':
          final size = tester.view.physicalSize / tester.view.devicePixelRatio;
          await tester.tapAt(Offset(
              (a['x']! as num) * size.width, (a['y']! as num) * size.height));
          await pumpFrames(16);
        case 'back':
          await tester.binding.handlePopRoute();
          await pumpFrames(16);
        case 'advance':
          await pumpFrames(a['ms']! as int);
        case 'set_profile':
          final size = a['size'];
          profile = Profile(
            width: size is List ? (size[0] as num).toDouble() : profile.width,
            height: size is List ? (size[1] as num).toDouble() : profile.height,
            dpr: (a['dpr'] as num?)?.toDouble() ?? profile.dpr,
            topInsetPx:
                (a['topInsetPx'] as num?)?.toDouble() ?? profile.topInsetPx,
            fontScale:
                (a['fontScale'] as num?)?.toDouble() ?? profile.fontScale,
            seed: profile.seed,
          );
          applyProfile();
          await pumpFrames(32);
        case 'wait_state':
          final timeout = a['timeoutMs']! as int;
          var waited = 0;
          late CheckResult last;
          while (true) {
            last = evaluate(state(), a);
            if (last.ok || waited >= timeout) break;
            await pumpFrames(16);
            waited += 16;
          }
          if (!last.ok) {
            throw StepFailure('wait_state timed out after $timeout ms of '
                'game time: ${last.message}');
          }
          message = '${last.message} (after $waited ms)';
        case 'expect':
          final r = evaluate(state(), a);
          checked++;
          if (!r.ok) {
            final why = a['why'];
            throw StepFailure('expect failed: ${r.message}'
                '${why is String ? ' ($why)' : ''}');
          }
          message = r.message;
        case 'expect_text':
          final text = a['text']! as String;
          final want = (a['count'] as int?) ?? 1;
          final got = find.text(text).evaluate().length;
          checked++;
          if (got != want) {
            throw StepFailure('expect_text "$text": wanted $want on screen, '
                'found $got.');
          }
          message = 'text "$text" appears $got time(s)';
        case 'shot':
          shots.add(await shot(a['name']! as String));
          message = shots.last;
      }
    } on StepFailure catch (f) {
      failure = 'step ${step.index} (${step.op}): ${f.message}';
      message = f.message;
    }
    final snapshot = state();
    steps.add({
      'step': step.index,
      'op': step.op,
      'ok': failure == null,
      'message': message,
      'state': snapshot,
    });
    trace.write(jsonEncode([step.index, step.op, snapshot]));
    if (failure != null) {
      try {
        shots.add(await shot('FAILED-step-${step.index}'));
      } catch (_) {
        // A picture is evidence only; never hide the real failure.
      }
      break;
    }
  }

  return RunOutcome(
    ok: failure == null,
    failure: failure,
    assertionsChecked: checked,
    gameClockMs: clockMs,
    traceSha256: sha256OfText(trace.toString()),
    shots: shots,
    steps: steps,
  );
}

Progress _loadSave(Setup setup, Directory kitDir) {
  Map<String, Object?> json = const {};
  if (setup.saveFixture != null) {
    final text = File('${kitDir.path}/${setup.saveFixture}').readAsStringSync();
    final d = jsonDecode(text);
    if (d is! Map<String, Object?>) {
      throw StateError('Save fixture ${setup.saveFixture} is not an object.');
    }
    json = d;
  } else if (setup.saveInline != null) {
    json = setup.saveInline!;
  }
  // A fixed first-open time keeps the state identical between runs.
  final withDate = Map<String, Object?>.of(json);
  final stats = Map<String, Object?>.of(
      (json['stats'] as Map?)?.cast<String, Object?>() ?? {});
  stats.putIfAbsent('firstOpenAt', () => '2026-01-01T00:00:00.000Z');
  withDate['stats'] = stats;
  return Progress.fromJson(withDate);
}

String _screenName(WidgetTester tester) {
  if (find.byType(GameWidget<ProbeGame>).evaluate().isNotEmpty) return 'game';
  if (find.text('PROBE DASH').evaluate().isNotEmpty) return 'home';
  return 'other';
}

String _overlay(WidgetTester tester) {
  if (find.text('CONTINUE?').evaluate().isNotEmpty) return 'revive';
  if (find.text('PLAY AGAIN').evaluate().isNotEmpty) return 'results';
  return 'none';
}

final RegExp _digit = RegExp(r'^[0-5]$');

Map<String, Object?> _buildState(
    WidgetTester tester, GameController c, int clockMs) {
  final onGame = find.byType(GameWidget<ProbeGame>).evaluate().isNotEmpty;
  final overlay = _overlay(tester);
  int? countdown;
  if (overlay == 'revive') {
    final digits = find.byWidgetPredicate(
        (w) => w is Text && _digit.hasMatch(w.data ?? ''));
    final hits = digits.evaluate();
    if (hits.length == 1) {
      countdown = int.parse((hits.single.widget as Text).data!);
    }
  }
  final p = c.progress;
  return {
    'clockMs': clockMs,
    'ui': {
      'screen': _screenName(tester),
      'overlay': overlay,
      'countdown': countdown,
    },
    'progress': {
      'runs': p.runs,
      'crystals': p.crystals,
      'bestM': p.bestDistance,
      'interstitialsShown': p.interstitialsShown,
      'removeAds': p.removeAds,
      'hapticsOn': p.hapticsOn,
    },
    if (onGame) 'game': gameOf(tester).testState(),
  };
}
