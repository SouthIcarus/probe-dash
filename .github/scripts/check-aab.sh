#!/usr/bin/env bash
# Guards for a release AAB (environments.md §5 step 20; ENV-5, ENV-12;
# security REL-2).
#
# Usage: check-aab.sh <aab> <test|real>
#   - signed, and NOT with the Android debug certificate (Play rejects it)
#   - 64-bit native libraries 16 KB aligned
#   - AdMob IDs: test only, or real ones present (prod)
# Logs only the certificate owner and SHA-256 fingerprint (CI-13).
set -euo pipefail

AAB="$1"
ADS="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0

cert=$(keytool -printcert -jarfile "$AAB" 2>&1 || true)
owner=$(grep -m1 '^Owner:' <<<"$cert" || true)
sha=$(grep -m1 'SHA256:' <<<"$cert" | sed 's/^[[:space:]]*//' || true)
echo "AAB: $AAB"
echo "  signer ${owner:-<none>}"
echo "  ${sha:-<no SHA-256>}"
if [[ -z "$owner" ]]; then
  echo "::error title=AAB check::$AAB is not signed"; fail=1
elif grep -q 'CN=Android Debug' <<<"$owner"; then
  echo "::error title=AAB check::$AAB is signed with the Android debug key; Play rejects it (ENV-5). Is the play-release keystore set?"; fail=1
fi

python3 -I "$HERE/check_16kb.py" "$AAB" || fail=1
python3 -I "$HERE/check_ad_ids.py" artifact "$AAB" --expect "$ADS" || fail=1

if (( fail )); then
  echo "AAB checks FAILED for $AAB"
  exit 1
fi
echo "AAB checks passed for $AAB"
