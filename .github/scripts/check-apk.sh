#!/usr/bin/env bash
# Guards for a built APK (environments.md §5 steps 11 and 20; security
# review SEC-6, SEC-20, SEC-21, REL-2, REL-3).
#
# Usage: check-apk.sh <apk> <expected-app-id> <test|real> [<version-code>]
#   - package name is <expected-app-id>
#   - targetSdkVersion >= 36 (Play minimum from 2026-08-31, F7)
#   - versionCode == <version-code>, if given
#   - permissions equal .github/android-permissions.txt
#   - 64-bit native libraries are 16 KB aligned (F8)
#   - AdMob IDs: test only, or real ones present (prod)
# Needs ANDROID_HOME (set on GitHub's ubuntu runners) for aapt2.
set -euo pipefail

APK="$1"
APP_ID="$2"
ADS="$3"
VERSION_CODE="${4:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MIN_TARGET_SDK=36

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
bt=$(find "$sdk/build-tools" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -1)
aapt2="$bt/aapt2"
[[ -x "$aapt2" ]] || { echo "::error::aapt2 not found under $sdk/build-tools"; exit 1; }

badging="$(mktemp)"
"$aapt2" dump badging "$APK" > "$badging"

fail=0
pkg=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" "$badging")
vc=$(sed -n "s/^package: .*versionCode='\([0-9]*\)'.*/\1/p" "$badging")
vn=$(sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p" "$badging")
target=$(sed -n "s/^targetSdkVersion:'\([0-9]*\)'.*/\1/p" "$badging")
echo "APK: $APK"
echo "  package=$pkg versionCode=$vc versionName=$vn targetSdk=$target"

if [[ "$pkg" != "$APP_ID" ]]; then
  echo "::error title=APK check::package is '$pkg', expected '$APP_ID'"; fail=1
fi
if [[ -z "$target" || "$target" -lt "$MIN_TARGET_SDK" ]]; then
  echo "::error title=APK check::targetSdkVersion '$target' is below $MIN_TARGET_SDK (Play requirement, ENV-12)"; fail=1
fi
if [[ -n "$VERSION_CODE" && "$vc" != "$VERSION_CODE" ]]; then
  echo "::error title=APK check::versionCode is '$vc', expected '$VERSION_CODE'"; fail=1
fi

python3 -I "$HERE/check_permissions.py" "$badging" "$HERE/../android-permissions.txt" --app-id "$APP_ID" || fail=1
python3 -I "$HERE/check_16kb.py" "$APK" || fail=1
python3 -I "$HERE/check_ad_ids.py" artifact "$APK" --expect "$ADS" || fail=1

if (( fail )); then
  echo "APK checks FAILED for $APK"
  exit 1
fi
echo "APK checks passed for $APK"
