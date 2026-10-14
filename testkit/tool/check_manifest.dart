// Compares two Probe Test Kit manifests: the one on the base branch and the
// one in this change. Exits 1 when a scenario was removed, lost assertions
// or changed and no reason was given.
//
//   dart run testkit/tool/check_manifest.dart --base base.json \
//       --head testkit/manifest.json [--reason "why"]
//
// CI feeds --reason from the line "TESTKIT-CHANGE: ..." in the PR body.
import 'dart:io';

import '../../test/testkit/src/manifest.dart';

void main(List<String> args) => exit(_run(args));

int _run(List<String> args) {
  String? base, head, reason;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--base':
        base = args[++i];
      case '--head':
        head = args[++i];
      case '--reason':
        reason = args[++i];
      default:
        stderr.writeln('Unknown argument ${args[i]}');
        return 2;
    }
  }
  if (base == null || head == null) {
    stderr.writeln('Usage: check_manifest.dart --base <file> --head <file> '
        '[--reason "..."]');
    return 2;
  }
  final Map<String, ManifestEntry> old, now;
  try {
    old = parseManifest(File(base).readAsStringSync());
    now = parseManifest(File(head).readAsStringSync());
  } on Object catch (e) {
    stderr.writeln('Cannot read a manifest: $e');
    return 2;
  }
  final problems = weakeningProblems(old, now);
  final added = unlisted(old, now);
  stdout.writeln('Scenarios: ${old.length} before, ${now.length} now. '
      'New: ${added.length}.');
  if (problems.isEmpty) {
    stdout.writeln('Ratchet holds: nothing removed, weakened or changed.');
    return 0;
  }
  for (final p in problems) {
    stdout.writeln('- $p');
  }
  if (reason != null && reason.trim().isNotEmpty) {
    stdout.writeln('Accepted with reason: ${reason.trim()}');
    return 0;
  }
  stdout.writeln('FAIL: add "TESTKIT-CHANGE: <reason>" to the PR description.');
  return 1;
}
