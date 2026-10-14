// Probe Test Kit: report.json and report.md. Pure Dart.
//
// report.json holds no clock time, so two runs of the same code with the
// same seeds produce identical text (acceptance test A2). Wall-clock times
// appear only in report.md.
import 'dart:convert';

/// How one scenario ended. FLAKY (failed once, passed on retry, or gave a
/// different state trace when repeated) counts as a failure.
enum Verdict { pass, fail, flaky }

class ScenarioReport {
  ScenarioReport({
    required this.id,
    required this.title,
    required this.covers,
    required this.canary,
    required this.verdict,
    required this.assertions,
    required this.assertionsChecked,
    required this.gameClockMs,
    required this.traceSha256,
    required this.shots,
    required this.attempts,
    this.failure,
    this.canaryFault,
    this.wallMs = 0,
  });

  final String id;
  final String title;
  final List<String> covers;
  final bool canary;
  final Verdict verdict;

  /// Assertions written in the file.
  final int assertions;

  /// Assertions that actually ran in the last attempt.
  final int assertionsChecked;

  /// Milliseconds of the game's fake clock used by the scenario.
  final int gameClockMs;

  /// Hash of the state seen after every step (the repeatability proof).
  final String traceSha256;
  final List<String> shots;
  final int attempts;
  final String? failure;

  /// Canary only: "failed-as-expected" or "did-not-fail" with the fault on.
  final String? canaryFault;
  final int wallMs;

  bool get ok => verdict == Verdict.pass &&
      (!canary || canaryFault == 'failed-as-expected');

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'covers': covers,
        'canary': canary,
        'result': verdict.name.toUpperCase(),
        'ok': ok,
        'attempts': attempts,
        'assertions': assertions,
        'assertionsChecked': assertionsChecked,
        'gameClockMs': gameClockMs,
        'traceSha256': traceSha256,
        'shots': shots,
        if (failure != null) 'failure': failure,
        if (canaryFault != null) 'canaryWithFault': canaryFault,
      };
}

class ReportHeader {
  const ReportHeader({
    required this.commit,
    required this.flutter,
    required this.dart,
    required this.fonts,
    required this.repeat,
    this.baselineScenarios,
    this.baselineAssertions,
    this.manifestProblems = const [],
  });

  final String commit;
  final String flutter;
  final String dart;

  /// "Roboto" when real fonts were loaded for pictures, else a warning.
  final String fonts;
  final int repeat;
  final int? baselineScenarios;
  final int? baselineAssertions;
  final List<String> manifestProblems;
}

int _count(List<ScenarioReport> r, bool Function(ScenarioReport) f) =>
    r.where(f).length;

/// Overall verdict: every scenario ok and the manifest ratchet holds.
bool overallOk(List<ScenarioReport> rows, ReportHeader h) =>
    rows.every((r) => r.ok) && h.manifestProblems.isEmpty;

String reportJson(List<ScenarioReport> rows, ReportHeader h) {
  final assertions = rows.fold<int>(0, (n, r) => n + r.assertions);
  const enc = JsonEncoder.withIndent('  ');
  return '${enc.convert({
        'kit': 'probe-test-kit',
        'schema': 1,
        'commit': h.commit,
        'flutter': h.flutter,
        'dart': h.dart,
        'fonts': h.fonts,
        'repeat': h.repeat,
        'verdict': overallOk(rows, h) ? 'PASS' : 'FAIL',
        'summary': {
          'scenarios': rows.length,
          'passed': _count(rows, (r) => r.verdict == Verdict.pass),
          'failed': _count(rows, (r) => r.verdict == Verdict.fail),
          'flaky': _count(rows, (r) => r.verdict == Verdict.flaky),
          'assertions': assertions,
          'baselineScenarios': h.baselineScenarios,
          'baselineAssertions': h.baselineAssertions,
        },
        'manifestProblems': h.manifestProblems,
        'scenarios': [for (final r in rows) r.toJson()],
      })}\n';
}

String _cell(String s) => s.replaceAll('|', '/').replaceAll('\n', ' ');

String reportMd(List<ScenarioReport> rows, ReportHeader h) {
  final ok = overallOk(rows, h);
  final assertions = rows.fold<int>(0, (n, r) => n + r.assertions);
  final b = StringBuffer()
    ..writeln('# Probe Test Kit report')
    ..writeln()
    ..writeln('**${ok ? 'PASS' : 'FAIL'}**: '
        '${_count(rows, (r) => r.ok)} of ${rows.length} scenarios ok, '
        '$assertions assertions'
        '${h.baselineScenarios == null ? '' : ' (baseline ${h.baselineScenarios} scenarios, ${h.baselineAssertions} assertions)'}.')
    ..writeln()
    ..writeln('Commit `${h.commit}` · Flutter ${h.flutter} · Dart ${h.dart} · '
        'fonts: ${h.fonts} · layer A (flutter_test, fake clock) · '
        'repeat ${h.repeat}')
    ..writeln()
    ..writeln('| Scenario | Layer | Result | Asserts | Game time | Wall time | '
        'Covers | Pictures |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final r in rows) {
    final result = r.canary
        ? '${r.verdict.name.toUpperCase()} / fault: ${r.canaryFault ?? 'not run'}'
        : r.verdict.name.toUpperCase();
    b.writeln('| ${_cell(r.id)} | A | $result | '
        '${r.assertionsChecked}/${r.assertions} | '
        '${(r.gameClockMs / 1000).toStringAsFixed(1)} s | '
        '${(r.wallMs / 1000).toStringAsFixed(1)} s | '
        '${_cell(r.covers.join(', '))} | '
        '${r.shots.isEmpty ? '-' : r.shots.length} |');
  }
  final bad = rows.where((r) => !r.ok).toList();
  if (bad.isNotEmpty || h.manifestProblems.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## What failed');
    for (final r in bad) {
      b.writeln('- **${r.id}** (${r.verdict.name.toUpperCase()}, covers '
          '${r.covers.join(', ')}): ${r.failure ?? r.canaryFault ?? 'see report.json'}');
    }
    for (final p in h.manifestProblems) {
      b.writeln('- **manifest**: $p');
    }
  }
  b
    ..writeln()
    ..writeln('Open a picture only for a FAIL or a layout claim. Pictures are '
        'evidence; the checks use the game state in `state/*.json`.');
  return b.toString();
}
