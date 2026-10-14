// Probe Test Kit: unit tests for the rules that sit under the runner (pure
// Dart): hashing, the scenario format, comparisons, the manifest ratchet and
// the report. One test group per rule.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'src/checks.dart';
import 'src/manifest.dart';
import 'src/report.dart';
import 'src/scenario.dart';
import 'src/sha256.dart';

const _okScenario = '''
{
  "id": "unit-ok",
  "title": "A valid scenario",
  "covers": ["A-20"],
  "steps": [
    { "do": "tap", "text": "PLAY" },
    { "do": "wait_state", "path": "ui.screen", "eq": "game", "timeoutMs": 1000 },
    { "do": "expect", "path": "game.phase", "eq": "ready" }
  ]
}
''';

String _with(String find, String replace) => _okScenario.replaceAll(find, replace);

Scenario _parse(String text, {String id = 'unit-ok'}) =>
    parseScenario(id, text, sha256: sha256OfText(text));

void _refused(String text, Pattern message, {String id = 'unit-ok'}) {
  expect(
      () => _parse(text, id: id),
      throwsA(isA<ScenarioError>()
          .having((e) => e.message, 'message', contains(message))));
}

void main() {
  group('sha256', () {
    test('matches the published test vectors', () {
      expect(sha256Hex(const []),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256Hex(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
          sha256Hex(utf8.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
    });

    test('line endings do not change a scenario hash', () {
      expect(sha256OfText('a\r\nb\r\n'), sha256OfText('a\nb\n'));
    });
  });

  group('scenario format', () {
    test('a valid file parses and counts its assertions', () {
      final s = _parse(_okScenario);
      expect(s.id, 'unit-ok');
      expect(s.steps, hasLength(3));
      expect(s.assertionCount, 1);
      expect(s.profile.width, 411);
      expect(s.canary, isFalse);
    });

    test('fixed sleeps are refused with a hint to use wait_state', () {
      for (final word in ['sleep', 'wait', 'delay', 'pause']) {
        _refused(_with('"do": "tap", "text": "PLAY"', '"do": "$word", "ms": 500'),
            'no fixed sleeps');
      }
    });

    test('a scenario with no expect cannot be loaded', () {
      _refused(
          _with('{ "do": "expect", "path": "game.phase", "eq": "ready" }',
              '{ "do": "advance", "ms": 10 }'),
          'cannot fail');
    });

    test('unknown fields and unknown steps are refused', () {
      _refused(_with('"covers"', '"colour": 1, "covers"'), 'unknown field');
      _refused(_with('"do": "tap", "text": "PLAY"', '"do": "swipe"'),
          'unknown step');
      _refused(_with('"text": "PLAY"', '"text": "PLAY", "speed": 3'),
          'has no field "speed"');
    });

    test('id must match the file name', () {
      _refused(_okScenario, 'must match', id: 'other-name');
    });

    test('bad numbers and missing limits name the step', () {
      _refused(
          _with('"do": "tap", "text": "PLAY"', '"do": "tap_at", "x": 2, "y": 0'),
          'step 1');
      _refused(_with(', "timeoutMs": 1000', ''), 'timeoutMs');
      _refused(_with('"eq": "game", ', '"eq": "game", "ne": "home", '),
          'exactly one');
    });

    test('invalid JSON and oversize files are refused', () {
      _refused('{ not json', 'not valid JSON');
      final big = _with('"title": "A valid scenario"',
          '"title": "${'x' * 100}", "covers2": "${'y' * (maxScenarioBytes + 10)}"');
      _refused(big, 'larger than');
    });

    test('canary flag is read', () {
      expect(_parse(_with('"covers"', '"canary": true, "covers"')).canary,
          isTrue);
    });

    test('every worked example in SCHEMA.md parses (agent-readable docs)', () {
      final md = File('testkit/SCHEMA.md').readAsStringSync();
      final blocks = RegExp(r'```json\n([\s\S]*?)```').allMatches(md).toList();
      expect(blocks.length, greaterThanOrEqualTo(3));
      for (final m in blocks) {
        final text = m.group(1)!;
        final id = (jsonDecode(text) as Map)['id'] as String;
        expect(() => _parse(text, id: id), returnsNormally, reason: id);
      }
    });

    test('every scenario file in the repo parses', () {
      final dir = Directory('testkit/scenarios');
      final files =
          dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final id = f.uri.pathSegments.last.replaceAll('.json', '');
        final text = f.readAsStringSync();
        expect(() => parseScenario(id, text, sha256: sha256OfText(text)),
            returnsNormally,
            reason: id);
      }
    });
  });

  group('state comparisons', () {
    final state = <String, Object?>{
      'game': {'phase': 'ready', 'distanceM': 15, 'hud': {'bestAhead': null}},
      'ui': {'overlay': 'none'},
    };

    CheckResult run(Map<String, Object?> args) => evaluate(state, args);

    test('eq, ne, ordering, contains, in and exists', () {
      expect(run({'path': 'game.phase', 'eq': 'ready'}).ok, isTrue);
      expect(run({'path': 'game.phase', 'ne': 'ready'}).ok, isFalse);
      expect(run({'path': 'game.distanceM', 'gte': 15}).ok, isTrue);
      expect(run({'path': 'game.distanceM', 'gt': 15}).ok, isFalse);
      expect(run({'path': 'game.distanceM', 'lte': 14}).ok, isFalse);
      expect(run({'path': 'game.distanceM', 'lt': 16}).ok, isTrue);
      expect(run({'path': 'game.phase', 'contains': 'ead'}).ok, isTrue);
      expect(run({'path': 'ui.overlay', 'in': ['none', 'revive']}).ok, isTrue);
      expect(run({'path': 'game.hud.bestAhead', 'eq': null}).ok, isTrue);
      expect(run({'path': 'game.hud.nothing', 'exists': false}).ok, isTrue);
      expect(run({'path': 'game.phase', 'exists': true}).ok, isTrue);
    });

    test('a missing path fails with a readable message, never passes', () {
      final r = run({'path': 'game.phasee', 'eq': 'ready'});
      expect(r.ok, isFalse);
      expect(r.message, contains('not in the state'));
      expect(run({'path': 'game.phase', 'gte': 1}).ok, isFalse);
    });

    test('the message shows what was found', () {
      expect(run({'path': 'game.distanceM', 'eq': 20}).message,
          'game.distanceM eq 20; found 15');
    });
  });

  group('manifest ratchet', () {
    ManifestEntry e(String id, int n, String h, {bool canary = false}) =>
        ManifestEntry(id, n, h, canary);

    final recorded = {
      'a': e('a', 5, 'h1'),
      'b': e('b', 3, 'h2', canary: true),
    };

    test('manifest text round-trips and is sorted', () {
      final text = manifestText([recorded['b']!, recorded['a']!]);
      final back = parseManifest(text);
      expect(back.keys, ['a', 'b']);
      expect(back['a']!.assertions, 5);
      expect(text.endsWith('\n'), isTrue);
      expect(text, contains('"scenarioCount": 2'));
      expect(text, contains('"assertionCount": 8'));
    });

    test('unchanged and a new scenario hold the ratchet', () {
      final now = {...recorded, 'c': e('c', 1, 'h3')};
      expect(weakeningProblems(recorded, now), isEmpty);
      expect(unlisted(recorded, now), ['c']);
    });

    test('removing a scenario is a problem', () {
      expect(weakeningProblems(recorded, {'a': recorded['a']!}),
          ['scenario "b" was removed']);
    });

    test('dropping an assertion is a problem (acceptance A5)', () {
      final now = {...recorded, 'a': e('a', 4, 'h9')};
      final p = weakeningProblems(recorded, now);
      expect(p.any((m) => m.contains('lost assertions (5 to 4)')), isTrue);
      expect(p.any((m) => m.contains('changed')), isTrue);
    });

    test('a changed hash alone is a problem', () {
      final now = {...recorded, 'a': e('a', 5, 'other')};
      expect(weakeningProblems(recorded, now), ['scenario "a" changed (hash differs)']);
    });

    test('unmarking the canary is a problem', () {
      final now = {...recorded, 'b': e('b', 3, 'h2')};
      expect(weakeningProblems(recorded, now),
          ['scenario "b" is no longer marked as a canary']);
    });

    test('a malformed manifest is refused', () {
      expect(() => parseManifest('{"scenarios": {"a": {"assertions": "x"}}}'),
          throwsFormatException);
      expect(() => parseManifest('[]'), throwsFormatException);
    });

    test('removing one expect from a real scenario fails against the '
        'recorded manifest (acceptance A5, on the real files)', () {
      final recordedReal =
          parseManifest(File('testkit/manifest.json').readAsStringSync());
      const id = 'revive-offer-then-decline';
      final text = File('testkit/scenarios/$id.json').readAsStringSync();
      final weaker = text.replaceFirst(
          RegExp(r'    \{ "do": "expect", "path": "progress.runs", "eq": 1 \},\r?\n'),
          '');
      expect(weaker, isNot(text), reason: 'the expect line must be found');
      final s = parseScenario(id, weaker, sha256: sha256OfText(weaker));
      final now = {
        ...recordedReal,
        id: ManifestEntry(id, s.assertionCount, s.sha256, false),
      };
      expect(weakeningProblems(recordedReal, now), isNotEmpty);
    });
  });

  group('report', () {
    ScenarioReport row(String id,
            {Verdict v = Verdict.pass,
            bool canary = false,
            String? fault,
            int wall = 1234}) =>
        ScenarioReport(
          id: id,
          title: 't',
          covers: const ['A-20'],
          canary: canary,
          verdict: v,
          assertions: 2,
          assertionsChecked: 2,
          gameClockMs: 1000,
          traceSha256: 'abc',
          shots: const [],
          attempts: 1,
          failure: v == Verdict.pass ? null : 'step 3 failed',
          canaryFault: fault,
          wallMs: wall,
        );

    const header = ReportHeader(
        commit: 'abc1234',
        flutter: '3.47.6',
        dart: '3.13.5',
        fonts: 'Roboto',
        repeat: 1,
        baselineScenarios: 2,
        baselineAssertions: 4);

    test('report.json holds no wall-clock time, so two runs are identical '
        '(acceptance A2)', () {
      final a = reportJson([row('x', wall: 100)], header);
      final b = reportJson([row('x', wall: 99999)], header);
      expect(a, b);
      expect(a, isNot(contains('wallMs')));
    });

    test('FLAKY counts as a failure', () {
      final rows = [row('x', v: Verdict.flaky)];
      expect(overallOk(rows, header), isFalse);
      expect(reportMd(rows, header), contains('FLAKY'));
      expect(reportJson(rows, header), contains('"verdict": "FAIL"'));
    });

    test('a canary that did not fail makes the run red', () {
      final rows = [row('c', canary: true, fault: 'did-not-fail')];
      expect(overallOk(rows, header), isFalse);
      final ok = [row('c', canary: true, fault: 'failed-as-expected')];
      expect(overallOk(ok, header), isTrue);
    });

    test('manifest problems turn the verdict red and are listed', () {
      const bad = ReportHeader(
          commit: 'c',
          flutter: 'f',
          dart: 'd',
          fonts: 'Roboto',
          repeat: 1,
          manifestProblems: ['scenario "a" was removed']);
      final rows = [row('x')];
      expect(overallOk(rows, bad), isFalse);
      expect(reportMd(rows, bad), contains('scenario "a" was removed'));
    });

    test('report.md starts with the verdict and has one table', () {
      final md = reportMd([row('x'), row('y', v: Verdict.fail)], header);
      expect(md, contains('**FAIL**: 1 of 2 scenarios ok'));
      expect(md, contains('| x | A | PASS | 2/2 |'));
      expect(md, contains('**y** (FAIL'));
    });
  });
}
