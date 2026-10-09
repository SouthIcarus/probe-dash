#!/usr/bin/env bash
# release.yml build step (environments.md §5 step 19; security CI-2).
#
# Env in:
#   FLAVOR, VERSION, BUILD_NUMBER, ARTIFACT   from the verify job
#   UPLOAD_KEYSTORE_PATH + passwords + alias  signing (Gradle reads them)
#   AD_IDS_FILE   optional: a JSON file in $RUNNER_TEMP with the real
#                 ADMOB_REWARDED_ID / ADMOB_INTERSTITIAL_ID (prod only)
#   ADMOB_APP_ID  optional: real app ID for the prod manifest (Gradle)
# Out: dist/ with the AAB, its SHA-256, the universal APK (launch test and
# guards only) and mapping/ (R8 mapping: workflow artifact only, SEC-15).
set -euo pipefail

: "${FLAVOR:?}" "${VERSION:?}" "${BUILD_NUMBER:?}" "${ARTIFACT:?}"

args=(--release --flavor "$FLAVOR"
      --dart-define-from-file="config/$FLAVOR.json"
      --build-name="$VERSION" --build-number="$BUILD_NUMBER")
if [[ -n "${AD_IDS_FILE:-}" ]]; then
  [[ "$FLAVOR" == prod ]] || { echo "::error::real ad IDs are only for prod (AD-3)"; exit 1; }
  args+=(--dart-define-from-file="$AD_IDS_FILE")
fi

flutter build appbundle "${args[@]}"
flutter build apk "${args[@]}"

mkdir -p dist/mapping
cp "build/app/outputs/bundle/${FLAVOR}Release/app-${FLAVOR}-release.aab" "dist/$ARTIFACT.aab"
cp "build/app/outputs/flutter-apk/app-${FLAVOR}-release.apk" "dist/$ARTIFACT-universal.apk"
(cd dist && sha256sum "$ARTIFACT.aab" > "$ARTIFACT.aab.sha256")
if [[ -f "build/app/outputs/mapping/${FLAVOR}Release/mapping.txt" ]]; then
  cp "build/app/outputs/mapping/${FLAVOR}Release/mapping.txt" "dist/mapping/$ARTIFACT-mapping.txt"
else
  echo "::warning::no R8 mapping file found"
fi
ls -l dist dist/mapping
