// Probe Test Kit: the manifest ratchet. The manifest lists every scenario
// with its assertion count and file hash. A scenario may not disappear, lose
// assertions or change without a stated reason ("TESTKIT-CHANGE: reason" in
// the PR). Pure Dart: used by the test run and by
// `testkit/tool/check_manifest.dart`.
import 'dart:convert';

class ManifestEntry {
  const ManifestEntry(this.id, this.assertions, this.sha256, this.canary);
  final String id;
  final int assertions;
  final String sha256;
  final bool canary;

  Map<String, Object?> toJson() => {
        'assertions': assertions,
        'canary': canary,
        'sha256': sha256,
      };
}

/// Builds the manifest text (stable order, trailing newline).
String manifestText(List<ManifestEntry> entries) {
  final sorted = [...entries]..sort((a, b) => a.id.compareTo(b.id));
  final assertionCount = sorted.fold<int>(0, (n, e) => n + e.assertions);
  const enc = JsonEncoder.withIndent('  ');
  final body = enc.convert({
    'version': 1,
    'scenarioCount': sorted.length,
    'assertionCount': assertionCount,
    'scenarios': {for (final e in sorted) e.id: e.toJson()},
  });
  return '$body\n';
}

/// Reads manifest text. Throws [FormatException] on a bad shape.
Map<String, ManifestEntry> parseManifest(String text) {
  final d = jsonDecode(text);
  if (d is! Map<String, Object?> || d['scenarios'] is! Map) {
    throw const FormatException('manifest.json has no "scenarios" object');
  }
  final out = <String, ManifestEntry>{};
  (d['scenarios']! as Map).forEach((id, v) {
    if (id is! String ||
        v is! Map ||
        v['assertions'] is! int ||
        v['sha256'] is! String) {
      throw FormatException('manifest entry "$id" is malformed');
    }
    out[id] = ManifestEntry(
        id, v['assertions'] as int, v['sha256'] as String, v['canary'] == true);
  });
  return out;
}

/// Why a scenario is not new: removed, weakened or changed compared with the
/// [recorded] manifest. Needs a "TESTKIT-CHANGE: reason" to be accepted.
List<String> weakeningProblems(
    Map<String, ManifestEntry> recorded, Map<String, ManifestEntry> current) {
  final problems = <String>[];
  for (final r in recorded.values) {
    final c = current[r.id];
    if (c == null) {
      problems.add('scenario "${r.id}" was removed');
      continue;
    }
    if (c.assertions < r.assertions) {
      problems.add('scenario "${r.id}" lost assertions '
          '(${r.assertions} to ${c.assertions})');
    }
    if (c.sha256 != r.sha256) {
      problems.add('scenario "${r.id}" changed (hash differs)');
    }
    if (r.canary && !c.canary) {
      problems.add('scenario "${r.id}" is no longer marked as a canary');
    }
  }
  return problems;
}

/// Scenarios on disk that the manifest does not list yet.
List<String> unlisted(
        Map<String, ManifestEntry> recorded, Map<String, ManifestEntry> current) =>
    [
      for (final c in current.values)
        if (!recorded.containsKey(c.id)) c.id,
    ];
