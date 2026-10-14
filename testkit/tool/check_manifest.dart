// Compares two Probe Test Kit manifests: the one on the base branch and the
// one in this change. Exits 1 when a scenario was removed, lost assertions
// or changed and no reason was given. The same holds for the kit's own files
// (test/testkit, lib/testkit, testkit/tool) listed under "kitFiles". Run it
// from the repo root.
//
//   dart run testkit/tool/check_manifest.dart --base base.json \
//       --head testkit/manifest.json [--reason "why"]
//
// CI feeds --reason from the line "TESTKIT-CHANGE: ..." in the PR body.
import 'dart:io';

import '../../test/testkit/src/kit_files.dart';
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
  final Map<String, String> oldKit, nowKit;
  try {
    final baseText = File(base).readAsStringSync();
    final headText = File(head).readAsStringSync();
    old = parseManifest(baseText);
    now = parseManifest(headText);
    oldKit = parseKitFiles(baseText);
    nowKit = parseKitFiles(headText);
  } on Object catch (e) {
    stderr.writeln('Cannot read a manifest: $e');
    return 2;
  }
  final problems = [
    ...weakeningProblems(old, now),
    ...kitFileProblems(oldKit, nowKit),
  ];
  // The recorded hashes must also be the real files, so a manifest that was
  // never refreshed (or was edited by hand) cannot hide a changed runner.
  final onDisk = hashKitFiles();
  final stale = [
    for (final e in nowKit.entries)
      if (onDisk[e.key] != e.value)
        'kit file "${e.key}" on disk does not match manifest.json '
            '(run TESTKIT_UPDATE_MANIFEST=1 flutter test test/testkit)',
    for (final p in onDisk.keys)
      if (!nowKit.containsKey(p))
        'kit file "$p" is not listed in manifest.json',
  ];
  final added = unlisted(old, now);
  stdout.writeln('Scenarios: ${old.length} before, ${now.length} now. '
      'New: ${added.length}. Kit files: ${oldKit.length} before, '
      '${nowKit.length} now.');
  if (stale.isNotEmpty) {
    for (final s in stale) {
      stdout.writeln('- $s');
    }
    stdout.writeln('FAIL: manifest.json is out of date.');
    return 1;
  }
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
