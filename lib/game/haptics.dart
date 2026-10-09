import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The game moments that vibrate (A-29). No haptic on thrust taps or single
/// crystals (fatigue and motor noise).
enum HapticKind { crash, shieldHit, nearMiss, newBest, upgradeBought }

/// A vibration as Android's waveform format: [timings] in milliseconds,
/// alternating off / on and starting with an "off" segment, and one
/// [amplitudes] value (0–255) per segment.
@immutable
class HapticPattern {
  /// [timings] and [amplitudes] must be the same length (unit-tested).
  const HapticPattern(this.timings, this.amplitudes);

  final List<int> timings;
  final List<int> amplitudes;

  /// Total milliseconds the motor is on.
  int get onMillis {
    var ms = 0;
    for (var i = 0; i < timings.length; i++) {
      if (amplitudes[i] > 0) ms += timings[i];
    }
    return ms;
  }

  /// Strongest amplitude in the pattern (255 = full strength).
  int get peakAmplitude => amplitudes.fold(0, (a, b) => a > b ? a : b);

  /// Number of separate pulses.
  int get pulses {
    var n = 0;
    for (var i = 0; i < timings.length; i++) {
      if (amplitudes[i] > 0 && timings[i] > 0) n++;
    }
    return n;
  }
}

/// Where haptics go. The app uses [PlatformHapticsBackend]; tests swap in a
/// recorder through [Haptics.backend].
abstract interface class HapticsBackend {
  void play(HapticKind kind);
}

/// Android: drives the vibration motor directly through the
/// `probe_dash/haptics` channel (MainActivity.kt), with explicit length and
/// strength per event.
///
/// Why not `HapticFeedback.heavyImpact()`: on Android Flutter maps it to
/// `View.performHapticFeedback(CONTEXT_CLICK)` (medium → KEYBOARD_TAP,
/// light → VIRTUAL_KEY). Those are short UI clicks the phone maker tunes;
/// on Samsung One UI they are barely felt and all feel alike, so the crash
/// was never a "strong buzz" (S26 checks 1 and 8).
///
/// Other platforms keep Flutter's [HapticFeedback] calls.
class PlatformHapticsBackend implements HapticsBackend {
  const PlatformHapticsBackend();

  static const MethodChannel channel = MethodChannel('probe_dash/haptics');

  @override
  void play(HapticKind kind) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      _fallback(kind);
      return;
    }
    final p = Haptics.patterns[kind]!;
    unawaited(_send(p));
  }

  static Future<void> _send(HapticPattern p) async {
    try {
      await channel.invokeMethod<bool>('vibrate', <String, Object>{
        'timings': p.timings,
        'amplitudes': p.amplitudes,
      });
    } on PlatformException catch (e) {
      debugPrint('Haptic failed: $e');
    } on MissingPluginException {
      // No native side (tests, or a platform without it): stay silent.
    }
  }

  static void _fallback(HapticKind kind) {
    switch (kind) {
      case HapticKind.crash:
        HapticFeedback.heavyImpact();
      case HapticKind.shieldHit:
      case HapticKind.newBest:
        HapticFeedback.mediumImpact();
      case HapticKind.nearMiss:
        HapticFeedback.lightImpact();
      case HapticKind.upgradeBought:
        HapticFeedback.selectionClick();
    }
  }
}

/// All game haptics go through here, so one switch turns them off.
///
/// On by default (owner decision D4, pending); the settings screen planned
/// with D3 will set [enabled].
class Haptics {
  Haptics._();

  /// The single on/off switch for game haptics.
  static bool enabled = true;

  /// Where haptics are sent. Tests replace it with a recorder.
  static HapticsBackend backend = const PlatformHapticsBackend();

  /// Length and strength per event (A-29). The crash is the only
  /// full-strength buzz; the near miss and the upgrade buy are light ticks.
  static const Map<HapticKind, HapticPattern> patterns = {
    // One strong buzz: 80 ms at full strength.
    HapticKind.crash: HapticPattern([0, 80], [0, 255]),
    // Medium: 40 ms at about two thirds.
    HapticKind.shieldHit: HapticPattern([0, 40], [0, 170]),
    // Light tick: 20 ms, low but still felt.
    HapticKind.nearMiss: HapticPattern([0, 20], [0, 110]),
    // Medium double pulse: 35 ms, 60 ms gap, 35 ms.
    HapticKind.newBest: HapticPattern([0, 35, 60, 35], [0, 170, 0, 170]),
    // Light tick for a successful purchase.
    HapticKind.upgradeBought: HapticPattern([0, 20], [0, 110]),
  };

  static void _play(HapticKind kind) {
    if (enabled) backend.play(kind);
  }

  static void crash() => _play(HapticKind.crash);

  static void shieldHit() => _play(HapticKind.shieldHit);

  static void nearMiss() => _play(HapticKind.nearMiss);

  /// The run just passed the player's best (A-29).
  static void newBest() => _play(HapticKind.newBest);

  /// An upgrade level was bought (A-29).
  static void upgradeBought() => _play(HapticKind.upgradeBought);
}
