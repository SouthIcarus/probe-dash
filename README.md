# Probe Dash

One-tap space runner for Android (iOS later). Tap to fire the thruster,
fly through asteroid gaps, collect crystals, and spend them on upgrades.

**Status:** Prototype. Test ads only. No in-app purchases yet.
**Spec:** `docs/products/probe-dash/spec.md` in `SouthIcarus/AJ_PROBE`.

## Install the prototype on an Android phone
1. Open this repo's **Releases** page on your phone and download the newest
   `probe-dash-proto-N.apk`.
2. Open the file. If Android asks, allow your browser to
   **install unknown apps**.
3. Tap **Install**.

## Develop
| Command | What |
|---|---|
| `flutter pub get` | Install packages |
| `flutter analyze` | Static checks |
| `flutter test` | Unit + widget tests (game rules are pure Dart in `lib/logic/`) |
| `flutter run` | Run on a connected phone or emulator |

## Code map
| Path | What |
|---|---|
| `lib/logic/` | Game rules: physics, gates, pickups, upgrades, progress, ad rules. No Flutter imports |
| `lib/game/` | Flame renderer and game loop |
| `lib/ui/` | Home, game (revive + results), upgrades screens |
| `lib/services/` | Save file, ads |
| `lib/app/` | App state controller |

Rules for every change: `CLAUDE.md`. History: `changelog.md`.
