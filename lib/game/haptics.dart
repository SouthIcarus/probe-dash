import 'package:flutter/services.dart';

/// All game haptics go through here, so one switch turns them off.
///
/// On by default (owner decision D4, pending); the settings screen planned
/// with D3 will set [enabled]. No haptic on thrust taps or single crystals
/// (fatigue and motor noise).
class Haptics {
  Haptics._();

  /// The single on/off switch for game haptics.
  static bool enabled = true;

  static void crash() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  static void shieldHit() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void nearMiss() {
    if (enabled) HapticFeedback.lightImpact();
  }
}
