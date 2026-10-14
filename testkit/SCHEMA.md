# Probe Test Kit: how to write a scenario

**TL;DR.** A scenario is one small JSON file in `testkit/scenarios/`. It plays
the real game on `flutter test` with a fake clock: tap, wait for the game to
reach a state, check numbers. Run everything with one command:

```
flutter test test/testkit
```

Then read `testkit-out/latest/report.md` (one table). Open a picture in
`testkit-out/latest/shots/` only for a FAIL or a layout question. The checks
use the game's **state**, not pixels.

Layer A only (this slice): `flutter_test`, the real screens, fake ads, a fake
save store, a fake clock. No phone, no browser.

## File rules

| Rule | Why |
|---|---|
| File name = `<id>.json`, `id` is lowercase letters, digits and dashes | One place to look; the report uses the id |
| `covers` lists at least one requirement ID (`"A-20"`) | Every check is tied to a spec line |
| At least one `expect` or `expect_text` step | A scenario that checks nothing cannot fail |
| **No fixed sleeps.** `sleep`, `wait`, `delay` are refused | Sleeps cause flaky tests. Use `wait_state` (waits for a state, with a time limit) or `advance` (moves the fake clock) |
| Unknown fields are refused | A typo must not silently disable a check |
| File at most 64 KB, at most 200 steps | Size is checked before use |
| Fake or invented data only | The repo is public |
| A scenario that fails once and passes on retry is **FLAKY** and counts as a failure | No "retry until green" |
| Never delete a scenario or an `expect` to get green | `manifest.json` records ids, assertion counts and file hashes; the test run fails when one drops or changes |
| **Adding a scenario needs one extra run with `TESTKIT_UPDATE_MANIFEST=1`** | The run fails with "not in manifest.json yet" until the new file is recorded. No reason is needed for a new scenario. See "Changing or removing a scenario" |
| Changing the kit itself (`test/testkit/`, `lib/testkit/`, `testkit/tool/`) needs a `TESTKIT-CHANGE:` line | Those files decide whether a scenario passes. `manifest.json` records their hashes under `kitFiles` |

## Top level

```
{
  "id": "my-scenario",                       // same as the file name
  "title": "One sentence in plain words",
  "covers": ["A-20"],                        // requirement IDs
  "canary": false,                           // optional, see Canary below
  "profile": { ... },                        // optional
  "setup":   { ... },                        // optional
  "steps":   [ ... ]
}
```

### profile (the phone)

| Field | Meaning | Default |
|---|---|---|
| `size` | `[width, height]` in dp | `[411, 891]` |
| `dpr` | pixel ratio | `2.63` |
| `topInsetPx` | camera-hole inset at the top, in physical pixels | `0` |
| `fontScale` | system text size multiplier | `1.0` |
| `seed` | whole number; same seed = same gates and pickups | `1` |

Samsung S26: `"size": [411, 891], "dpr": 2.628, "topInsetPx": 84` or
`"size": [360, 780], "dpr": 3, "topInsetPx": 84`.

### setup

| Field | Meaning |
|---|---|
| `save` | `"fixtures/fresh.json"` (a file in `testkit/fixtures/`) or an inline object with the save fields, for example `{ "bestDistance": 60, "crystals": 500 }` |
| `ads.rewardedReady` | `true` (default) = a rewarded ad is loaded; `false` = none, so a crash goes straight to results |
| `ads.rewardedWatchResult` | `true` = the player watches the ad to the end and earns the reward |
| `ads.interstitialLoaded` | `true` = a full-screen ad is loaded, so the 6th, 9th, 12th... run shows it (default `false`). Use a save with `stats.runs` of 5 to reach run 6 in one crash |

The scenario starts on the **Home** screen. Tap `PLAY` to reach the game.

## Steps

Each step is an object with `"do"` plus its fields.

| Step | Fields | What it does |
|---|---|---|
| `tap` | `text`, optional `times` (1 to 5) | Taps the widget showing exactly that text. `times` taps land inside one frame (a double tap). Fails with a plain message if the text is missing or not tappable yet |
| `tap_at` | `x`, `y` (0 to 1) | Taps a point as a fraction of the screen. In the game this is the thrust tap |
| `back` | none | The Android back gesture |
| `advance` | `ms` (1 to 120000) | Moves the fake clock forward in 16 ms frames |
| `wait_state` | `path`, one comparison, `timeoutMs` | Advances frame by frame until the state matches; fails at the limit. Counts game time, not real time |
| `expect` | `path`, one comparison, optional `why` | Checks the state now. Counts as one assertion |
| `expect_text` | `text`, optional `count` (default 1) | Checks how many widgets show exactly that text. Counts as one assertion |
| `shot` | `name` | Saves a picture to `shots/<id>-<name>.png`. After a crash wait about 400 ms (`advance`) so the panel has faded in |
| `set_profile` | any of `size`, `dpr`, `topInsetPx`, `fontScale` | Changes the phone mid-scenario. Do it on the Home screen, before PLAY |

**Comparisons** (use exactly one): `eq`, `ne`, `gt`, `gte`, `lt`, `lte`
(numbers), `contains` (text), `exists` (true or false), `in` (a list).

## The state you can check

`path` uses dots, for example `game.hud.bestAhead`.

**These paths are frozen as schema 1** (`"schema": 1` in `game.*`). A path may
be added; none is renamed or removed within schema 1. A change that must
break a path bumps the schema number and is a `TESTKIT-CHANGE`.

**`ui.*` is read from on-screen text.** `ui.screen`, `ui.overlay` and
`ui.countdown` are worked out from what the screen shows ("CONTINUE?",
"PLAY AGAIN", "PROBE DASH", a single digit), not from a state variable. If
the game's wording changes, scenarios that use `ui.*` or `tap`/`expect_text`
on that wording fail until the new text is put in `testState()` or the
scenario. Treat a copy change as a kit change. `progress.*` and `game.*` come
from the game's numbers and do not depend on wording.

| Path | Meaning |
|---|---|
| `clockMs` | Fake clock time used so far |
| `ui.screen` | `home`, `game`, or `other` |
| `ui.overlay` | `none`, `revive` (CONTINUE? panel) or `results` |
| `ui.countdown` | Revive countdown number 0 to 5, or null |
| `progress.runs` | Runs counted in the save |
| `progress.crystals` | Saved crystals |
| `progress.bestM` | Saved best distance in meters |
| `progress.interstitialsShown` | Full-screen ads counted |
| `progress.removeAds`, `progress.hapticsOn` | Settings and entitlements |
| `game.*` | Only while the game screen is open (see below) |

`game.*` comes from `ProbeGame.testState()`:

| Path | Meaning |
|---|---|
| `game.phase` | `ready`, `playing`, `crashed`, `over` |
| `game.distanceM` | Whole meters this run |
| `game.bestM` | Best at the start of this run |
| `game.crystals` | Crystals collected this run |
| `game.nearMisses`, `game.gatesPassed`, `game.shieldHitsLeft` | Run counters |
| `game.reviveUsed`, `game.canRevive`, `game.passedBest` | Flags |
| `game.probe.x`, `game.probe.y`, `game.probe.vy` | Probe position and speed (world units) |
| `game.nextGate.x`, `.gapTop`, `.gapBottom` | The next gate not yet passed (world units; null if none) |
| `game.screen.w`, `game.screen.h` | Game size in dp |
| `game.hud.top` | Top of the HUD in dp |
| `game.hud.insetTop` | Camera-hole inset in dp |
| `game.hud.clearOfInset` | HUD top minus inset (the spec wants at least 8) |
| `game.hud.bestLine` | `"BEST 60 m"`, `"NEW BEST"`, or null |
| `game.hud.bestAhead` | `"BEST 50 m ahead"` while the gold line is off screen, else null |
| `game.hud.bestMarkerOnScreen` | The gold line is visible |
| `game.hud.newBestBanner` | The NEW BEST banner is showing |

If you need a number that is not here, do not guess: ask for it to be added to
`testState()` (a small change in `lib/game/probe_game.dart`).

## Canary

A scenario with `"canary": true` must **pass** on a good build and must
**fail** when the kit's deliberate fault is switched on (the run counter
counts twice). The runner switches the fault on itself and the report shows
`PASS / fault: failed-as-expected`. If the canary does not fail with the
fault, the whole run is red: the kit cannot be trusted.

## Changing or removing a scenario

1. Edit, add or remove the scenario (or a kit file).
2. Record the new hashes: `TESTKIT_UPDATE_MANIFEST=1 flutter test test/testkit`
   (PowerShell: `$env:TESTKIT_UPDATE_MANIFEST=1; flutter test test/testkit`).
   The run that rewrites the manifest can show one red test about the old
   manifest; run `flutter test test/testkit` again and it must be green.
   **Adding a scenario needs this step too.**
3. In the PR description write `TESTKIT-CHANGE: <why>` when a scenario was
   removed, lost an assertion or changed, or when any file in `test/testkit/`,
   `lib/testkit/` or `testkit/tool/` changed. Adding a scenario without
   touching those files needs no reason.

Checking two manifests (what CI should run, see `CI-PROPOSAL.txt`):

```
dart run testkit/tool/check_manifest.dart --base <old manifest.json> --head testkit/manifest.json [--reason "..."]
```

## Worked examples

### 1. Crash and decline the revive

```json
{
  "id": "example-decline-revive",
  "title": "Crash, decline the revive, one run is counted",
  "covers": ["A-20"],
  "profile": { "size": [411, 891], "dpr": 2.63, "topInsetPx": 84, "seed": 42 },
  "setup": { "save": "fixtures/fresh.json", "ads": { "rewardedReady": true } },
  "steps": [
    { "do": "tap", "text": "PLAY" },
    { "do": "wait_state", "path": "ui.screen", "eq": "game", "timeoutMs": 2000 },
    { "do": "tap_at", "x": 0.5, "y": 0.5 },
    { "do": "wait_state", "path": "ui.overlay", "eq": "revive", "timeoutMs": 15000 },
    { "do": "advance", "ms": 400 },
    { "do": "tap", "text": "No thanks" },
    { "do": "expect", "path": "progress.runs", "eq": 1 }
  ]
}
```

### 2. A saved best and the HUD note

```json
{
  "id": "example-best-note",
  "title": "With a best of 60 m the HUD shows BEST 60 m",
  "covers": ["A-04"],
  "setup": { "save": { "bestDistance": 60 } },
  "steps": [
    { "do": "tap", "text": "PLAY" },
    { "do": "wait_state", "path": "ui.screen", "eq": "game", "timeoutMs": 2000 },
    { "do": "expect", "path": "game.hud.bestLine", "eq": "BEST 60 m" },
    { "do": "shot", "name": "best-line" }
  ]
}
```

### 3. Back during a run

```json
{
  "id": "example-back-during-run",
  "title": "Back during a run ends it and shows results",
  "covers": ["FEEL-03"],
  "setup": { "ads": { "rewardedReady": false } },
  "steps": [
    { "do": "tap", "text": "PLAY" },
    { "do": "wait_state", "path": "ui.screen", "eq": "game", "timeoutMs": 2000 },
    { "do": "tap_at", "x": 0.5, "y": 0.5 },
    { "do": "advance", "ms": 100 },
    { "do": "back" },
    { "do": "advance", "ms": 1000 },
    { "do": "expect", "path": "ui.overlay", "eq": "results" },
    { "do": "expect", "path": "progress.runs", "eq": 1 }
  ]
}
```

## If a run fails

`report.md` names the scenario, the step number and what was expected against
what was found, for example `expect failed: progress.runs eq 1; found 2`.
`state/<id>.json` has the full state after every step, and
`shots/<id>-FAILED-step-N.png` shows the screen at the failing step.
A file that cannot be read fails with a message that names the file and the
step, for example `Scenario "x", step 3: "sleep" is not allowed`.
