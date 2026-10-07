#!/usr/bin/env bash
# Usage: launch-test.sh <apk> <application-id>
# Installs the APK on the running emulator, opens it, and checks it is still
# alive after 30 seconds. Prints crash and error logs either way.
set -uo pipefail

APK="$1"
APP_ID="$2"

adb logcat -c
adb install -r "$APK" || { echo "::error::APK failed to install"; exit 1; }
adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1

alive=1
for i in $(seq 1 30); do
  sleep 1
  if ! adb shell pidof "$APP_ID" >/dev/null; then
    alive=0
    echo "App process gone after ${i}s"
    break
  fi
done

echo "===== Crash buffer ====="
adb logcat -d -b crash || true
echo "===== Errors and Flutter output ====="
adb logcat -d '*:E' flutter:V AndroidRuntime:V DEBUG:V | tail -n 300 || true

if (( alive )); then
  echo "App still running after 30s."
  exit 0
fi
echo "::error::App closed within 30 seconds of opening. See logs above."
exit 1
