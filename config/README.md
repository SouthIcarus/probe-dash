# Build config (non-secret)

One file per flavor, passed with `--dart-define-from-file`:

```bash
flutter run   --flavor dev  --dart-define-from-file=config/dev.json
flutter build apk --release --flavor dev --dart-define-from-file=config/dev.json
```

| Key | dev | beta | prod | Read by |
|---|---|---|---|---|
| `FLAVOR` | `dev` | `beta` | `prod` | `lib/config/env.dart` |
| `ADS_MODE` | `test` | `test` (ENV-D2) | `real` | `EnvConfig.adUnitIds` |
| `ANALYTICS` | `off` (AN-6) | `on` | `on` | `EnvConfig.analyticsEnabled` (used from PR B) |
| `BUILD_LABEL` | `DEV` | `BETA` | empty | Home build label (UI-2) |
| `DEBUG_MENU` | `false` | `false` | `false` | `EnvConfig.debugMenuEnabled` (dev only; no menu exists yet) |

**Never put a secret or a real AdMob ID in these files** (spec v3 AD-3,
OPS-2). Real ad unit IDs reach only prod builds made by `release.yml`,
from the `play-release` environment's secrets. Outside prod the app
replaces any non-test ID with Google's test ID at runtime, and the repo
guard (`.github/scripts/check_ad_ids.py`) fails any commit that adds one.
