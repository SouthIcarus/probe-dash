// Probe Test Kit: same seed, same result (risk R5, acceptance A2), and the
// runner's failure messages are readable (acceptance A10, part 2).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'src/runner.dart';
import 'src/scenario.dart';
import 'src/sha256.dart';

Scenario _fromText(String id, String text) =>
    parseScenario(id, text, sha256: sha256OfText(text));

Scenario _fromFile(String id) =>
    _fromText(id, File('testkit/scenarios/$id.json').readAsStringSync());

String _inline(String steps, {String id = 'inline-check'}) => '''
{
  "id": "$id",
  "title": "inline",
  "covers": ["KIT-1"],
  "profile": { "seed": 7 },
  "steps": [ $steps ]
}''';

void main() {
  final kit = Directory('testkit');
  final shots = Directory('testkit-out/repeatability/shots');

  setUpAll(loadPictureFonts);

  testWidgets('20 runs of one scenario give 20 identical state traces',
      (tester) async {
    final s = _fromFile('revive-offer-then-decline');
    final hashes = <String>{};
    for (var i = 0; i < 20; i++) {
      final out =
          await runScenario(tester, s, kitDir: kit, shotsDir: shots);
      expect(out.ok, isTrue, reason: 'run ${i + 1}: ${out.failure}');
      hashes.add(out.traceSha256);
    }
    expect(hashes, hasLength(1));
  });

  testWidgets('a different seed gives a different trace (the seed is used)',
      (tester) async {
    final a = _fromFile('revive-offer-then-decline');
    final text = File('testkit/scenarios/revive-offer-then-decline.json')
        .readAsStringSync()
        .replaceFirst('"seed": 42', '"seed": 43');
    final b = _fromText('revive-offer-then-decline', text);
    final ra = await runScenario(tester, a, kitDir: kit, shotsDir: shots);
    final rb = await runScenario(tester, b, kitDir: kit, shotsDir: shots);
    expect(ra.ok && rb.ok, isTrue);
    expect(ra.traceSha256, isNot(rb.traceSha256));
  });

  testWidgets('a failing expect names the step, the path and what was found',
      (tester) async {
    final s = _fromText(
        'inline-check',
        _inline('{ "do": "expect", "path": "progress.runs", "eq": 5, '
            '"why": "planted" }'));
    final out = await runScenario(tester, s, kitDir: kit, shotsDir: shots);
    expect(out.ok, isFalse);
    expect(out.failure,
        'step 1 (expect): expect failed: progress.runs eq 5; found 0 '
        '(planted)');
    expect(out.shots.single, contains('FAILED-step-1'));
  });

  testWidgets('tapping text that is not on screen says where it is',
      (tester) async {
    final s = _fromText(
        'inline-check',
        _inline('{ "do": "tap", "text": "No thanks" }, '
            '{ "do": "expect", "path": "ui.screen", "eq": "home" }'));
    final out = await runScenario(tester, s, kitDir: kit, shotsDir: shots);
    expect(out.ok, isFalse);
    expect(out.failure, contains('no such text on screen'));
    expect(out.failure, contains('Screen: home'));
  });

  testWidgets('wait_state gives up at its limit, in game time',
      (tester) async {
    final s = _fromText(
        'inline-check',
        _inline('{ "do": "wait_state", "path": "ui.screen", "eq": "game", '
            '"timeoutMs": 300 }, '
            '{ "do": "expect", "path": "ui.screen", "eq": "game" }'));
    final out = await runScenario(tester, s, kitDir: kit, shotsDir: shots);
    expect(out.ok, isFalse);
    expect(out.failure, contains('wait_state timed out after 300 ms'));
    expect(out.gameClockMs, lessThan(1000));
  });

  testWidgets('the state is plain JSON the agents can read', (tester) async {
    final s = _fromText(
        'inline-check',
        _inline('{ "do": "tap", "text": "PLAY" }, '
            '{ "do": "wait_state", "path": "ui.screen", "eq": "game", '
            '"timeoutMs": 1000 }, '
            '{ "do": "expect", "path": "game.phase", "eq": "ready" }'));
    final out = await runScenario(tester, s, kitDir: kit, shotsDir: shots);
    expect(out.ok, isTrue, reason: out.failure);
    final game = (out.steps.last['state']! as Map)['game'] as Map;
    expect(jsonDecode(jsonEncode(game)), game);
    expect(game.keys, containsAll(['phase', 'distanceM', 'hud', 'probe']));
  });
}
