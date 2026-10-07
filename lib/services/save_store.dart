import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/progress.dart';

/// Saves [Progress] as JSON in the app's documents folder (GAME-6).
///
/// Writes go to a temp file first and are then renamed over the real one,
/// so a crash mid-write never leaves a half-written save.
class SaveStore {
  SaveStore([this._directory]);

  Directory? _directory;
  Future<void> _pending = Future.value();

  Future<File> _file() async {
    _directory ??= await getApplicationDocumentsDirectory();
    return File('${_directory!.path}/save.json');
  }

  Future<Progress> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return Progress();
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) return Progress.fromJson(json);
    } catch (e) {
      debugPrint('Save load failed, starting fresh: $e');
    }
    return Progress();
  }

  /// Queues a save; saves never overlap.
  Future<void> save(Progress progress) {
    final data = jsonEncode(progress.toJson());
    _pending = _pending.then((_) async {
      try {
        final file = await _file();
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(data, flush: true);
        await tmp.rename(file.path);
      } catch (e) {
        debugPrint('Save failed: $e');
      }
    });
    return _pending;
  }
}
