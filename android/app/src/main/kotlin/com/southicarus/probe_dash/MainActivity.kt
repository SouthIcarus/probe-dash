package com.southicarus.probe_dash

import android.annotation.TargetApi
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Game haptics (spec A-29) go straight to the vibration motor through the
 * `probe_dash/haptics` channel. Flutter's HapticFeedback uses
 * View.performHapticFeedback UI clicks, which Samsung One UI plays as faint,
 * near-identical ticks; the game needs a clearly strong crash buzz.
 *
 * Method `vibrate`: `timings` (ms, off/on alternating, starting with off)
 * and `amplitudes` (0-255, one per timing). Returns true if it vibrated.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "vibrate" -> {
                        val timings = call.argument<List<Number>>("timings")
                            ?.map { it.toLong() }
                        val amplitudes = call.argument<List<Number>>("amplitudes")
                            ?.map { it.toInt() }
                        if (timings == null || timings.isEmpty() || amplitudes == null ||
                            timings.size != amplitudes.size
                        ) {
                            result.error(
                                "bad_args",
                                "timings and amplitudes must be non-empty and the same length",
                                null,
                            )
                        } else {
                            result.success(vibrate(timings, amplitudes))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    private fun vibrate(timings: List<Long>, amplitudes: List<Int>): Boolean {
        val v = vibrator() ?: return false
        if (!v.hasVibrator()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(effect(v, timings, amplitudes))
            } else {
                // API 24-25: on/off pattern only, no strength control.
                @Suppress("DEPRECATION")
                v.vibrate(timings.toLongArray(), -1)
            }
            true
        } catch (e: RuntimeException) {
            false // e.g. SecurityException or a bad pattern: no haptic
        }
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun effect(v: Vibrator, timings: List<Long>, amplitudes: List<Int>): VibrationEffect {
        val amps = if (v.hasAmplitudeControl()) {
            amplitudes.map { it.coerceIn(0, 255) }
        } else {
            amplitudes.map { if (it > 0) VibrationEffect.DEFAULT_AMPLITUDE else 0 }
        }
        // A single pulse after a zero-length "off" is a plain one-shot.
        if (timings.size == 2 && timings[0] == 0L && amps[1] != 0 && timings[1] > 0) {
            return VibrationEffect.createOneShot(timings[1], amps[1])
        }
        return VibrationEffect.createWaveform(timings.toLongArray(), amps.toIntArray(), -1)
    }

    companion object {
        private const val CHANNEL = "probe_dash/haptics"
    }
}
