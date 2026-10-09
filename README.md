# Probe Dash

One-tap space runner for Android (iOS later). Tap to fire the thruster,
fly through asteroid gaps, collect crystals, and spend them on upgrades.

**Status:** Prototype. Test ads only. No in-app purchases yet.
**Spec:** the latest approved spec in `docs/products/probe-dash/` of
`SouthIcarus/AJ_PROBE` (currently `spec.v3.md`).

## Environments
| Flavor | App ID | Name on the phone | Ads | Built by |
|---|---|---|---|---|
| `dev` | `com.southicarus.probe_dash.dev` | Probe Dash Dev (DEV icon) | Google test ads | `Build` on every push; `dev-N` pre-release on `main` |
| `beta` | `com.southicarus.probe_dash` | Probe Dash | Google test ads | `release.yml` from an owner tag `beta-vX.Y.Z+N` |
| `prod` | `com.southicarus.probe_dash` | Probe Dash | Real (CI secrets only) | `release.yml` from an owner tag `vX.Y.Z+N` |

Non-secret settings are in `config/<flavor>.json` (see `config/README.md`).
Nothing in this repo needs a secret: tests and local runs use test ads.

## Install the dev build on an Android phone
1. Open this repo's **Releases** page on your phone and download the newest
   `probe-dash-dev-N.apk`.
2. Open the file. If Android asks, allow your browser to
   **install unknown apps**.
3. Tap **Install**. It installs as **"Probe Dash Dev"**, a separate app
   next to any old "Probe Dash" prototype (`proto-N`) already on the
   phone; progress does not carry over. Uninstall the old prototype when
   you no longer need it (it must go before the Play build is installed).

## Develop
| Command | What |
|---|---|
| `flutter pub get --enforce-lockfile` | Install the locked packages |
| `flutter analyze` | Static checks |
| `flutter test` | Unit + widget tests (game rules are pure Dart in `lib/logic/`) |
| `flutter run --flavor dev --dart-define-from-file=config/dev.json` | Run the dev app on a connected phone or emulator |
| `flutter build apk --release --flavor dev --dart-define-from-file=config/dev.json` | Build the dev APK as CI does |

## Code map
| Path | What |
|---|---|
| `lib/logic/` | Game rules: physics, gates, pickups, upgrades, progress, ad rules. No Flutter imports |
| `lib/game/` | Flame renderer and game loop |
| `lib/ui/` | Home, game (revive + results), upgrades screens |
| `lib/services/` | Save file, ads |
| `lib/app/` | App state controller |
| `lib/config/` | Build environment (flavor, ad IDs, labels). No Flutter imports |
| `config/` | Non-secret per-flavor settings |
| `.github/` | CI: `Repo rules`, `Build`, `Launch test`, `release.yml` (dry-run by default), guard scripts |

Rules for every change: `CLAUDE.md`. History: `changelog.md`.
