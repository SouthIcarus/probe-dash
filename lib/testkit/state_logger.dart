import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Prints one `PROBE_STATE {json}` line whenever the run phase changes and
/// at most once per [everySeconds] of game time otherwise (Probe Test Kit).
///
/// It is created only when `env.testkitEnabled` is true (dev flavor and
/// `TESTKIT=true`), so beta and prod builds never print the line. Agents
/// read it from the browser console (web) or `adb logcat` (Android).
class StateLogger {
  StateLogger({void Function(String line)? sink, this.everySeconds = 1.0})
      : _sink = sink ?? debugPrint;

  /// The word every line starts with.
  static const String prefix = 'PROBE_STATE';

  final void Function(String line) _sink;
  final double everySeconds;
  double _sinceLast = 0;
  String? _lastPhase;

  /// Call once per frame. [state] is only built when a line is printed.
  void tick(double dt, String phase, Map<String, Object?> Function() state) {
    _sinceLast += dt;
    if (phase != _lastPhase || _sinceLast >= everySeconds) {
      _lastPhase = phase;
      _sinceLast = 0;
      _sink('$prefix ${jsonEncode(state())}');
    }
  }
}
