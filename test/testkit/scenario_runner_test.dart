// Probe Test Kit, layer A: runs every scenario in testkit/scenarios/ and
// writes testkit-out/latest/{report.json,report.md,state/*.json,shots/*.png}.
//
//   flutter test test/testkit
//
// Environment (all optional):
//   TESTKIT_REPEAT=3          run each scenario 3 times; a different state
//                             trace between repeats is FLAKY (a failure)
//   TESTKIT_UPDATE_MANIFEST=1 rewrite testkit/manifest.json from the files
//   TESTKIT_CHANGE="reason"   accept removed/weakened/changed scenarios
//                             (the PR body must carry the same reason)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'src/kit_files.dart';
import 'src/manifest.dart';
import 'src/report.dart';
import 'src/runner.dart';
import 'src/scenario.dart';
import 'src/sha256.dart';

final Directory kitDir = Directory('testkit');
final Directory outDir = Directory('testkit-out/latest');

/// Parsed scenarios, or the reason a file was refused.
class Loaded {
  Loaded(this.id, this.scenario, this.error);
  final String id;
  final Scenario? scenario;
  final String? error;
}

List<Loaded> loadScenarios() {
  final dir = Directory('${kitDir.path}/scenarios');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      () {
        final id = f.uri.pathSegments.last.replaceAll('.json', '');
        final text = f.readAsStringSync();
        try {
          return Loaded(
              id, parseScenario(id, text, sha256: sha256OfText(text)), null);
        } on ScenarioError catch (e) {
          return Loaded(id, null, e.message);
        }
      }(),
  ];
}

String _commit() {
  try {
    final r = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    if (r.exitCode == 0) return (r.stdout as String).trim();
  } catch (_) {}
  return 'unknown';
}

String _flutterVersion() {
  final root = Platform.environment['FLUTTER_ROOT'];
  try {
    if (root != null) {
      final j = jsonDecode(
          File('$root/bin/cache/flutter.version.json').readAsStringSync());
      return (j as Map)['frameworkVersion'] as String;
    }
  } catch (_) {}
  return 'unknown';
}

void main() {
  final repeat =
      int.tryParse(Platform.environment['TESTKIT_REPEAT'] ?? '') ?? 1;
  final loaded = loadScenarios();
  final reports = <ScenarioReport>[];
  var fonts = 'not loaded';
  var manifestProblems = <String>[];
  int? baselineScenarios, baselineAssertions;

  setUpAll(() async {
    fonts = await loadPictureFonts();
  });

  for (final item in loaded) {
    if (item.scenario == null) {
      // A file that cannot be used is a red test that names the file.
      test('scenario ${item.id} (invalid file)', () {
        reports.add(ScenarioReport(
          id: item.id,
          title: '(invalid file)',
          covers: const [],
          canary: false,
          verdict: Verdict.fail,
          assertions: 0,
          assertionsChecked: 0,
          gameClockMs: 0,
          traceSha256: '',
          shots: const [],
          attempts: 0,
          failure: item.error,
        ));
        fail(item.error!);
      });
      continue;
    }
    final s = item.scenario!;
    testWidgets('scenario ${s.id}', (tester) async {
      final watch = Stopwatch()..start();
      final shotsDir = Directory('${outDir.path}/shots');
      Future<RunOutcome> once({bool fault = false}) => runScenario(tester, s,
          kitDir: kitDir, shotsDir: shotsDir, fault: fault);

      var attempts = 1;
      var last = await once();
      var verdict = last.ok ? Verdict.pass : Verdict.fail;
      var failure = last.failure;
      if (!last.ok) {
        // One retry only to tell FLAKY from a plain failure; both are red.
        attempts++;
        final again = await once();
        if (again.ok) {
          verdict = Verdict.flaky;
          failure = 'failed once, passed on retry. First failure: '
              '${last.failure}';
          last = again;
        } else {
          last = again;
        }
      } else {
        for (var i = 1; i < repeat; i++) {
          attempts++;
          final again = await once();
          if (!again.ok || again.traceSha256 != last.traceSha256) {
            verdict = Verdict.flaky;
            failure = 'repeat ${i + 1} of $repeat gave a different result '
                '(${again.ok ? 'different state trace' : again.failure})';
            break;
          }
        }
      }

      String? canaryFault;
      if (s.canary && verdict == Verdict.pass) {
        final faulty = await once(fault: true);
        canaryFault = faulty.ok ? 'did-not-fail' : 'failed-as-expected';
        if (faulty.ok) {
          failure = 'canary DID NOT FAIL with the fault switched on: '
              'the kit cannot be trusted';
        }
      }

      final stateDir = Directory('${outDir.path}/state')
        ..createSync(recursive: true);
      File('${stateDir.path}/${s.id}.json').writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({
        'scenario': s.id,
        'result': verdict.name.toUpperCase(),
        'steps': last.steps,
      })}\n');

      final row = ScenarioReport(
        id: s.id,
        title: s.title,
        covers: s.covers,
        canary: s.canary,
        verdict: verdict,
        assertions: s.assertionCount,
        assertionsChecked: last.assertionsChecked,
        gameClockMs: last.gameClockMs,
        traceSha256: last.traceSha256,
        shots: last.shots,
        attempts: attempts,
        failure: failure,
        canaryFault: canaryFault,
        wallMs: watch.elapsedMilliseconds,
      );
      reports.add(row);
      expect(row.ok, isTrue, reason: failure ?? 'canary check failed');
    });
  }

  test('manifest ratchet: no scenario removed, weakened or changed', () {
    final current = <String, ManifestEntry>{
      for (final l in loaded)
        if (l.scenario != null)
          l.id: ManifestEntry(l.id, l.scenario!.assertionCount,
              l.scenario!.sha256, l.scenario!.canary),
    };
    final file = File('${kitDir.path}/manifest.json');
    final kitNow = hashKitFiles();
    final update = Platform.environment['TESTKIT_UPDATE_MANIFEST'] == '1';
    if (update) {
      file.writeAsStringSync(
          manifestText(current.values.toList(), kitFiles: kitNow));
    }
    final recorded = parseManifest(file.readAsStringSync());
    final recordedKit = parseKitFiles(file.readAsStringSync());
    baselineScenarios = recorded.length;
    baselineAssertions = recorded.values.fold<int>(0, (n, e) => n + e.assertions);
    final reason = Platform.environment['TESTKIT_CHANGE'] ?? '';
    final problems = <String>[
      if (reason.trim().isEmpty && !update)
        ...weakeningProblems(recorded, current),
      if (reason.trim().isEmpty && !update)
        ...kitFileProblems(recordedKit, kitNow),
      // A new kit file is not a weakening, but it must be recorded.
      for (final p in kitNow.keys)
        if (!recordedKit.containsKey(p))
          'kit file "$p" is not in manifest.json yet (run once with '
              'TESTKIT_UPDATE_MANIFEST=1 and commit the file)',
      for (final id in unlisted(recorded, current))
        'scenario "$id" is not in manifest.json yet (run once with '
            'TESTKIT_UPDATE_MANIFEST=1 and commit the file)',
    ];
    manifestProblems = problems;
    expect(problems, isEmpty, reason: problems.join('; '));
  });

  tearDownAll(() {
    reports.sort((a, b) => a.id.compareTo(b.id));
    final header = ReportHeader(
      commit: _commit(),
      flutter: _flutterVersion(),
      dart: Platform.version.split(' ').first,
      fonts: fonts,
      repeat: repeat,
      baselineScenarios: baselineScenarios,
      baselineAssertions: baselineAssertions,
      manifestProblems: manifestProblems,
    );
    outDir.createSync(recursive: true);
    File('${outDir.path}/report.json')
        .writeAsStringSync(reportJson(reports, header));
    File('${outDir.path}/report.md')
        .writeAsStringSync(reportMd(reports, header));
  });
}
