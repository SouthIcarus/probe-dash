#!/usr/bin/env bash
# Usage: launch-test.sh <apk> <application-id>
# Installs the APK on the running emulator, opens it, and checks it is still
# alive after 30 seconds. Then taps the middle of the screen once and checks
# it is still alive 10 seconds later. Saves pictures of the screen to shots/
# (the workflow uploads them), so a person can see what the game showed
# without a phone. Prints crash and error logs either way.
set -uo pipefail

APK="$1"
APP_ID="$2"

mkdir -p shots
# A picture of the emulator screen. Never fails the test: a missing picture
# is a nuisance, not a broken game.
shot() { adb exec-out screencap -p > "shots/$1.png" 2>/dev/null || true; }

adb logcat -c
adb install -r "$APK" || { echo "::error::APK failed to install"; exit 1; }
adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1

alive=1
for i in $(seq 1 30); do
  sleep 1
  if (( i == 10 )); then shot 1-after-10s; fi
  if ! adb shell pidof "$APP_ID" >/dev/null; then
    alive=0
    echo "App process gone after ${i}s"
    break
  fi
done

tapped=1
if (( alive )); then
  shot 2-after-30s
  # One tap in the middle of the screen (the size comes from the emulator
  # itself; only digits are used), then a look at what it led to.
  size=$(adb shell wm size | tr -d '\r' | grep -oE '[0-9]+x[0-9]+' | tail -n 1)
  w=${size%x*}; h=${size#*x}
  if [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]]; then
    adb shell input tap $(( w / 2 )) $(( h / 2 ))
    sleep 3
    shot 3-after-tap
    sleep 7
    shot 4-ten-seconds-after-tap
    if ! adb shell pidof "$APP_ID" >/dev/null; then
      tapped=0
      echo "App process gone within 10s of a tap in the middle of the screen"
    fi
  else
    echo "Could not read the screen size; the tap was skipped."
  fi
fi

echo "===== Crash buffer ====="
adb logcat -d -b crash || true
echo "===== Errors and Flutter output ====="
adb logcat -d '*:E' flutter:V AndroidRuntime:V DEBUG:V | tail -n 300 || true

if (( alive && tapped )); then
  echo "App still running after 30s, and after a tap."
  exit 0
fi
if (( alive )); then
  echo "::error::App closed within 10 seconds of a tap in the middle of the screen. See logs above."
  exit 1
fi
echo "::error::App closed within 30 seconds of opening. See logs above."
exit 1
