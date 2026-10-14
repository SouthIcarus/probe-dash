// Probe Test Kit: finds the kit's own source files and hashes them, so that
// manifest.json can record them (see manifest.dart). Plain Dart: used by the
// test run and by `testkit/tool/check_manifest.dart`.
import 'dart:io';

import 'sha256.dart';

/// Folders whose `.dart` files are the kit itself. Anything that decides
/// whether a scenario passes lives in one of these.
const List<String> kitFileRoots = [
  'test/testkit',
  'lib/testkit',
  'testkit/tool',
];

/// Repo-relative path (forward slashes) to hash, for every `.dart` file under
/// [kitFileRoots] below [root]. Line endings are normalised by
/// [sha256OfText], so the hash is the same on Windows and Linux.
Map<String, String> hashKitFiles([String root = '.']) {
  final out = <String, String>{};
  final prefix = '${root.replaceAll('\\', '/')}/';
  for (final r in kitFileRoots) {
    final dir = Directory('$root/$r');
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      var rel = f.path.replaceAll('\\', '/');
      if (rel.startsWith(prefix)) rel = rel.substring(prefix.length);
      out[rel] = sha256OfText(f.readAsStringSync());
    }
  }
  return out;
}
