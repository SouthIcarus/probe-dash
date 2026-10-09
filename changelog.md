# Probe Dash Changelog

Append-only log of every decision, note, and change in Probe Dash.
Rules: see `CLAUDE.md`. **Never edit or delete existing entries**: add a
new entry that references the old one instead. Newest entries at the bottom.

**Entry types:** `DECISION` · `NOTE` · `CHANGE` · `VERSION` · `DEPRECATE` ·
`DELETE` · `BLOCKER` · `LEARNING`

**Template:**

```
## #NNNN — YYYY-MM-DD — TYPE — Short title
- **What:** what happened / was decided
- **Why:** the reason
- **Files:** files affected (or "none")
- **Refs:** related entry IDs, commits, spec requirement IDs (optional)
```

---

## #0001 — 2026-10-07 — DECISION — Repo created with AJ_PROBE rules
- **What:** Owner created the private `probe-dash` repo for the game's code
  (AJ_PROBE decision D1: each product gets its own repo; the spec stays in
  `SouthIcarus/AJ_PROBE` at `docs/products/probe-dash/spec.md`). Added the
  same governance as AJ_PROBE: `CLAUDE.md` rules, this append-only
  changelog, the `Repo rules` GitHub check, and Claude deny rules for
  deletion commands. The check's exempt list also covers Flutter's
  generated `.dart_tool/`, `pubspec.lock`, and `Podfile.lock`.
- **Why:** Same traceability and no-delete rules for product code as for
  AJ_PROBE.
- **Files:** `CLAUDE.md`, `changelog.md`, `.github/workflows/repo-rules.yml`,
  `.github/scripts/check-repo-rules.sh`, `.claude/settings.json`
- **Refs:** AJ_PROBE #0018 (G3), #0020

## #0002 — 2026-10-07 — CHANGE — Playable prototype (spec launch step L2)
- **What:** Flutter 3.47.6 + Flame 1.38 app with: one-tap flying with
  fixed-step physics (GAME-1); always-passable asteroid gates that speed up
  and tighten with distance (GAME-2); crystals, near-miss bonus, magnet
  pickups; 4 upgrades × 10 levels (Crystal Value, Shield, Magnet, Head
  Start); once-per-run revive via rewarded ad with a 5s countdown (US-1);
  results screen with 2× crystals ad; interstitial rules (AD-1); Google
  consent form (AD-2); Google test ad IDs only (AD-3); "No ad available"
  fallbacks (AD-4); crash-safe local save (GAME-6). Vector-shape art.
  30 unit/widget tests. `Build` workflow: analyze + test on every push;
  on main, builds an APK and publishes it as a GitHub pre-release.
- **Why:** Spec L2 fun-gate: the owner plays it on Android to decide
  whether it earns "one more run" before more is built.
- **Not in the prototype (by design):** in-app purchases (need a Play
  developer account and store products first), skins, daily missions,
  streak, starter pack, revive tokens, real art, sound.
- **Spec deviation:** Shield also grants post-hit invincibility that grows
  0.1s per level (1.1s at Lv1), so levels between the spec's hit
  thresholds (Lv1/5/10) still improve something.
- **Files:** `lib/`, `test/`, `android/`, `ios/`, `pubspec.yaml`,
  `.github/workflows/build.yml`, `README.md`
- **Refs:** spec GAME-1/2/6, US-1, US-3, AD-1–4

## #0003 — 2026-10-07 — LEARNING — Difficulty check with a bot player
- **What:** A scripted bot that always aims for the next gap's centre ran
  8 seeded runs: it died between 1,711 m and 3,389 m (67–117 s), passing
  53–114 gates and collecting 104–264 crystals. A first version of the bot
  that tapped too early passed 0 gates: it kept clipping the top edge.
- **Why it matters:** Each tap lifts the probe about 15.5 units, so good
  play means tapping ~7 units below the gap centre. Humans will die far
  sooner than the bot, which puts typical runs near the spec's 30–90 s.
  At ~20–60 crystals per human run, the first upgrade (100–250) takes 2–5
  runs. Re-check both after the owner plays.
- **Files:** none
- **Refs:** spec GAME-2, §2

## #0004 — 2026-10-07 — NOTE — Prototype signing and install limits
- **What:** Prototype APKs are signed with a debug key cached in GitHub
  Actions, so a new APK installs over the old one and keeps progress. If
  the cache expires (7 days without a build), the next APK needs the old
  one uninstalled first. Real release signing (an upload key kept in
  GitHub secrets, never in the repo) is required before the Play Store.
- **Why:** Lets the owner test without setting up secrets yet.
- **Files:** `.github/workflows/build.yml`
- **Refs:** #0002

## #0005 — 2026-10-07 — BLOCKER — Prototype build 3 closes as soon as it opens
- **What:** Owner installed `probe-dash-proto-3.apk` on an Android phone;
  the app closes immediately every time. The APK's manifest checks out
  (AdMob test app ID present, permissions normal, minSdk 24), so the cause
  needs a real crash log. Claude can't run an emulator in its own
  environment (Google's SDK download server is blocked there), so added a
  `Launch test` workflow: GitHub builds the release APK, installs it on an
  Android 11 emulator, opens it, fails if it isn't running 30 seconds
  later, and prints the crash log.
- **Why:** Get the actual error instead of guessing, and stop any future
  build that crashes on launch from reaching the owner's phone. Unit and
  widget tests can't catch this: they don't run the Android app.
- **Files:** `.github/workflows/launch-test.yml`, `.github/scripts/launch-test.sh`
- **Refs:** #0002

## #0006 — 2026-10-07 — NOTE — Crash device: Galaxy S26 (Android 16); 16 KB pages ruled out
- **What:** Owner's phone is a Samsung Galaxy S26 (base model), which runs
  Android 16. Checked the prime suspect for new phones, 16 KB memory pages:
  all three arm64 native libraries in build 3 (`libflutter.so`,
  `libapp.so`, `libdartjni.so`) are 16 KB-aligned and stored uncompressed
  at 16 KB offsets, so that is not the cause. The launch test now runs on
  Android 11, 15, and 16 emulators instead of 11 only.
- **Why:** The crash may depend on the Android version; testing only
  Android 11 could miss it.
- **Files:** `.github/workflows/launch-test.yml`
- **Refs:** #0005

## #0007 — 2026-10-07 — CHANGE — Fix launch crash: keep WorkManager's database class
- **What:** The launch test reproduced the crash on the Android 11
  emulator: `FATAL EXCEPTION: main ... Unable to get provider
  androidx.startup.InitializationProvider ... Failed to create an instance
  of androidx.work.impl.WorkDatabase`. WorkManager (a dependency of the
  Google Mobile Ads SDK) starts automatically when the app process starts
  and builds its database by looking up the generated `WorkDatabase_Impl`
  class by name. The release build's code shrinker (R8) stripped that
  class's constructor, so the app died before showing anything. Added
  `android/app/proguard-rules.pro` keeping every Room database class and
  its constructor, and wired it into the release build.
- **Why:** Root-cause fix for #0005. Not specific to the Galaxy S26: every
  release build crashed on every phone.
- **Learning:** Release builds shrink code; debug builds and unit tests
  don't. A crash that only exists in the shrunk build is invisible to
  `flutter test`. The launch test now runs the real release APK on every
  push and PR, so this class of bug can't ship again.
- **Files:** `android/app/proguard-rules.pro`, `android/app/build.gradle.kts`
- **Refs:** #0005, #0006

## #0008 — 2026-10-08 — CHANGE — One run, one result; one tap, one upgrade level
- **What:** (1) `RunSession.finish()` now returns the same `RunResult` on
  repeated calls without recalculating. (2) `GameScreen._finish()` has a
  guard flag, so a run is applied to progress exactly once even when a
  double tap on "No thanks" or a tap as the revive countdown hits 0 reach
  it twice. (3) Upgrades: `GameController.buyUpgrade` ignores a buy while
  the previous one is still saving, and each tile ignores taps for 400 ms
  after a buy (A-22), so a fast double tap buys one level, not two.
  New tests: `test/game_screen_test.dart` (double tap, countdown race),
  `test/upgrades_screen_test.dart` (taps 100 ms apart, in-flight buy),
  `finish()` idempotence in `run_session_test.dart`; shared fakes in
  `test/support/fakes.dart`.
- **Why:** UX review UX-21/A-20 and UX-23/A-22: both paths corrupted the
  economy (crystals and `runs` counted twice, which also skews interstitial
  pacing AD-1). UX plan PR 1 item 1.
- **Agent:** engineer
- **Files:** `lib/logic/run_session.dart`, `lib/ui/game_screen.dart`,
  `lib/app/game_controller.dart`, `lib/ui/upgrades_screen.dart`,
  `test/game_screen_test.dart`, `test/upgrades_screen_test.dart`,
  `test/support/fakes.dart`, `test/logic/run_session_test.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #1; `ux-review.md` A-20, A-22; spec US-3, GAME-6, AD-1

## #0009 — 2026-10-08 — CHANGE — Back gesture mid-run ends the run instead of losing it
- **What:** `GameScreen` is wrapped in `PopScope`. Back may leave the
  screen only before the first tap (`ready`) or once results show. A back
  gesture while playing or crashed (revive offer) goes through the normal
  `_finish()` path: the run is saved and the results screen shows. Back
  while a rewarded ad is in flight is ignored. No pause state is added
  (owner decision D1 is pending). Tests use `handlePopRoute()` for back
  mid-run, back on the revive offer, and back before the first tap.
- **Why:** FEEL-03 / UX-07 (A-07): an accidental edge swipe closed the game
  mid-run, so the run was never counted and its crystals were lost. The
  UX review's A-07 proposes a PAUSED panel; per the brief, that waits for
  D1, and this PR uses the existing finish path instead.
- **Agent:** engineer
- **Files:** `lib/ui/game_screen.dart`, `test/game_screen_test.dart`,
  `test/support/fakes.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #2, D1; `ux-review.md` A-07; spec §7, GAME-6

## #0010 — 2026-10-08 — CHANGE — Crash beat and 400 ms input lock on overlays
- **What:** On a crash the game now plays a 500 ms crash beat before any
  overlay appears: camera shake (300 ms, up to 1.5 world units, linear
  decay), a white flash (25% alpha fading over 120 ms) and 12 debris
  triangles (side 1.2 u, white-blue and orange, 20–40 u/s, fading over
  500 ms), all drawn with shapes in `ProbeGame` and render-only. After the
  beat the revive offer or the results appear. Each overlay fades in over
  250 ms and ignores all taps for its first 400 ms (`IgnorePointer`).
  Tests: overlay absent at 400 ms and present at 550 ms after the crash;
  taps on "No thanks" / "Watch ad to revive" 100 ms after it appears do
  nothing (no ad shown, run not applied); PLAY AGAIN ignores an early tap.
- **Why:** FEEL-01 / UX-01 / UX-02 (A-01): the crash froze with no impact,
  and taps the player was already making landed on the overlay buttons,
  starting unwanted ads (an AdMob policy risk) or skipping results.
  The brief sets the lock at 400 ms; the UX review's A-01 says 350 ms.
  400 ms was used as briefed.
- **Agent:** engineer
- **Files:** `lib/game/probe_game.dart`, `lib/ui/game_screen.dart`,
  `test/game_screen_test.dart`, `test/support/fakes.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #3; `ux-review.md` A-01; spec AD-3, §7

## #0011 — 2026-10-08 — CHANGE — No ad loaded: skip the revive offer; ad buttons update live
- **What:** (1) After the crash beat, the revive offer shows only if a
  revive is unused **and** a rewarded ad is loaded; otherwise the game goes
  straight to results. (2) `AdService` exposes `rewardedReadyListenable`
  (`ValueListenable<bool>`), updated whenever a rewarded ad loads, is
  shown, or fails. The revive button and the results "2× crystals" button
  rebuild from it, so they switch from "No ad available" to active as soon
  as an ad finishes loading. AD-4's "No ad available" fallback stays on the
  2× button. Tests run with ads disabled and with a fake `AdService` that
  flips readiness.
- **Why:** A-08 / UX-09: with no ad, players waited 5 s in front of a
  disabled button; spec §7 already says "Crashed --> Results: No revive
  available". A-09 / UX-10: the buttons read the ad state once and stayed
  stale. The UX review lists A-08 as needing owner OK (D-UX-1); the UX
  plan puts it in PR 1 as within spec §7, so it is built as briefed.
- **Agent:** engineer
- **Files:** `lib/services/ad_service.dart`, `lib/ui/game_screen.dart`,
  `test/game_screen_test.dart`, `test/support/fakes.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #4; `ux-review.md` A-08, A-09, D-UX-1; spec §7, AD-4, US-1

## #0012 — 2026-10-08 — CHANGE — Game screen fits the phone: immersive mode, inset HUD, visible deadly floor
- **What:** (1) Entering `GameScreen` sets `SystemUiMode.immersiveSticky`;
  leaving it restores `SystemUiMode.edgeToEdge`. (2) The screen passes
  `MediaQuery.viewPaddingOf(context)` to `ProbeGame`; the HUD top is
  `max(height × 0.05, inset top + 8 dp)` (exposed as `ProbeGame.hudTop`,
  pure helper `hudTopFor`), and the HUD also clears a left inset. (3) The
  revive/results panels sit inside `SafeArea`. (4) The deadly floor is
  drawn as a red band (`#FF5252`, 70% alpha) from y = 98.5 u to the bottom
  with a solid 0.4 u top line; the ceiling stays safe and undrawn. The
  A-05 "pulse during the first 3 runs" was not built (not in the brief).
  Tests: HUD top ≥ 48 with a 48 dp inset; 5% without; immersive on enter
  and edge-to-edge on leave via a mocked platform channel.
- **Why:** FEEL-11 / UX-06 (A-06): the status bar drew over the HUD and the
  gesture handle over the floor. FEEL-09 / UX-05 (A-05): the bottom edge
  kills but wasn't drawn, so deaths looked like they happened "on nothing".
- **Agent:** engineer
- **Files:** `lib/game/probe_game.dart`, `lib/ui/game_screen.dart`,
  `test/game_screen_test.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #5; `ux-review.md` A-05, A-06

## #0013 — 2026-10-08 — CHANGE — Run events and game feel: haptics, shake, hit-stop, particles, near-miss pop-up
- **What:** `RunSession` (pure Dart, `lib/logic`) records a `RunEvent`
  per occurrence: `crash`, `shieldHit`, `nearMiss`, `crystal`, `magnet`,
  `floorBounce`, `newBest` (once per run, only when a best exists, same
  floor rule as the results' "NEW BEST!"), `headStartEnd` (once, only with
  Head Start). `RunSession` now takes the player's `bestDistance`.
  `ProbeGame` drains the events after each update and turns them into
  render-only feedback: crash → heavy haptic + the crash beat from #0010
  (now event-driven); shield hit → medium haptic, 0.25 s decaying shake
  (1 u) and an 80 ms hit-stop; near miss → light haptic (max one per
  300 ms, A-29) and a "CLOSE! +2 ◆" pop-up (orange, rises 6 u, fades over
  700 ms, max 2 on screen, A-03); crystal → 4 cyan sparks over 250 ms
  (A-17), no haptic. All haptics go through `lib/game/haptics.dart` with one
  `Haptics.enabled` switch, on by default. `magnet`, `floorBounce` and
  `headStartEnd` have no feedback yet (their A-14/A-15 designs are not in
  PR 1); `newBest` is used by the next change. No physics or Tuning value
  changed. Tests: one unit test per event (exactly once per occurrence),
  plus widget tests that a crash sends one heavy impact and the switch
  silences it.
- **Why:** A-00 (shared prerequisite), A-03, FEEL-07, A-29: crashes and
  near misses gave no feedback, so the game "feels cheap" and the
  near-miss reward was invisible. Haptics default follows the pending
  owner decision D4 (recommended "on"); the switch lets D3's settings
  screen add a toggle later.
- **Agent:** engineer
- **Files:** `lib/logic/run_session.dart`, `lib/game/probe_game.dart`,
  `lib/game/haptics.dart` (new), `test/logic/run_session_test.dart`,
  `test/game_screen_test.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #6, D3, D4; `ux-review.md` A-00, A-03, A-17, A-29; #0010

## #0014 — 2026-10-08 — CHANGE — Best-distance chase: HUD line, labelled marker, NEW BEST! banner
- **What:** While the player has a best, the HUD shows "BEST <n> m" in
  gold (`#FFD54F`, `size.y × 0.022`) under the distance; once passed it
  reads "NEW BEST". The in-world best marker is now 1.0 u wide at full
  alpha with a "BEST" label at its top (was 0.6 u, 53% alpha, unlabelled).
  On the `newBest` run event (#0013) a "NEW BEST!" banner appears at 30%
  screen height (`size.y × 0.045`), scales 0.6× → 1.0× over 150 ms, holds
  800 ms, and fades over 300 ms. Tests: best-line text, banner
  scale/alpha curve, and a widget test that passing the best shows the
  banner and it clears after ~1.25 s. Thousands separators (A-25) are not
  part of PR 1.
- **Why:** A-04 / UX-04: the record was invisible until <1 s before
  reaching it and passing it gave no moment; "chase your own record" is
  the core hook (spec §2).
- **Agent:** engineer
- **Files:** `lib/game/probe_game.dart`, `test/game_screen_test.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #7; `ux-review.md` A-04; spec §2, §8; #0013

## #0015 — 2026-10-08 — CHANGE — Smooth rendering between physics steps
- **What:** `RunSession` keeps the scroll, probe height and pickup
  positions from before each fixed step and exposes
  `alpha = accumulator / fixedStep` (clamped 0..1; 1 outside `playing`)
  plus interpolated `renderScroll`, `renderProbeY`, `renderPickupX/Y`
  (hand-written lerp, still no Flutter in `lib/logic`). The previous state
  is reset to the current one in the constructor and in `revive()`, so the
  probe never streaks from the crash spot. `ProbeGame` draws stars, gates,
  pickups, the best marker, particles and the probe from the interpolated
  values. Physics is unchanged: the existing determinism tests pass, a new
  test runs whole vs. 1.5-step updates to the same state, and a seeded bot
  run (4 seeds, shield/magnet/head start on) printed bit-identical final
  states on `origin/main` and this branch.
- **Why:** FEEL-02: with 120 Hz physics drawn at the screen's refresh rate,
  the drawn position jumped by 0 or 2 steps on some frames (~2 visible
  stutters per second in the tech lead's simulation).
- **Agent:** engineer
- **Files:** `lib/logic/run_session.dart`, `lib/game/probe_game.dart`,
  `test/logic/run_session_test.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #8; spec GAME-1

## #0016 — 2026-10-08 — CHANGE — Probe stays visible while invincible; square rock corners
- **What:** (1) During invincibility (revive / shield grace) the probe's
  "off" blink phase draws it at 35% opacity instead of not drawing it
  (same 0.2 s blink cycle; pure helper `ProbeGame.probeOpacity`, unit
  tested to never return 0). (2) Rock gates are drawn with square corners
  (were 3 u rounded), so the art matches the square hitbox. No hit radius,
  look-ahead, or `Tuning` value changed.
- **Why:** FEEL-08 / UX-12: the probe vanished for half of each blink,
  making steering through the next gap guesswork. FEEL-05 (art only): the
  rounded art hid up to ~10 dp of rock that still killed ("invisible rock"
  deaths). The hitbox side of FEEL-05 is for the later tuning PR (D2).
- **Agent:** engineer
- **Files:** `lib/game/probe_game.dart`, `test/game_screen_test.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #9, D2; `ux-review.md` A-11

## #0017 — 2026-10-08 — CHANGE — Results screen shows an "Upgrade ready" shortcut
- **What:** When the player can afford an upgrade after a run, the results
  panel shows an outlined button under PLAY AGAIN, e.g. "Upgrade ready:
  Crystal Value Lv1 – 100 ◆", naming the cheapest affordable next level
  (ties follow the spec §4 table order); it opens the Upgrades screen.
  Nothing shows when no upgrade is affordable. New pure helper
  `Upgrades.cheapestAffordable(levels, crystals)` with unit tests; widget
  tests for the shown/hidden cases and that it opens Upgrades. Placed under
  PLAY AGAIN as in the spec §8 wireframe. The A-18 "Next upgrade: … to go"
  text for the not-affordable case was not built (brief: hide it).
- **Why:** Spec §8 ResultsScreen wireframe lists "UpgradesShortcut"; it was
  missing (A-18 / UX-19), weakening the "one more upgrade" hook at the
  moment the player has crystals.
- **Agent:** engineer
- **Files:** `lib/logic/upgrades.dart`, `lib/ui/game_screen.dart`,
  `test/logic/upgrades_test.dart` (new), `test/game_screen_test.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #10; `ux-review.md` A-18; spec §8, US-3

## #0018 — 2026-10-08 — CHANGE — Cheaper rendering and instant "Play again" on the same game
- **What:** (1) HUD text uses cached `TextPainter`s that are laid out again
  only when their text, size or colour changes; fading text (pop-ups,
  banner) fades through a layer instead of a new layout; digits use
  tabular figures. Painters are disposed in `ProbeGame.onDispose`.
  (2) Paints are static or reused (no `Paint()` per draw call), paths are
  reused, and one shared `Random` serves the thruster flicker, effects and
  the star field (the flicker created a new `Random` every frame).
  (3) "Play again" calls `ProbeGame.newRun(upgradeLevels:, bestDistance:)`
  on the same game instead of building a new game and `GameWidget`.
  (4) `GameController.completeRun` applies the run and queues the save
  without awaiting it, so results show at once; `SaveStore` still writes
  saves in order (GAME-6). Tests: Play again keeps the same `GameWidget`
  element and game, returns to `ready` and carries the new best; results
  appear while a save is still pending; HUD text is not re-laid out over
  20 unchanged frames.
- **Why:** FEEL-12: per-frame `TextPainter` layouts and allocations cause
  frame spikes. FEEL-13 / GAME-4: restarting remounted the game widget;
  reusing it makes "one more run" instant.
- **Agent:** engineer
- **Files:** `lib/game/probe_game.dart`, `lib/ui/game_screen.dart`,
  `lib/app/game_controller.dart`, `test/game_screen_test.dart`
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #11; spec GAME-4, GAME-6

## #0019 — 2026-10-08 — CHANGE — QA failure-path tests for UX PR 1
- **What:** Added `test/qa_failure_paths_test.dart` (14 tests): revive then
  a second crash goes to results with no second offer and applies the run
  once; the revive countdown stays paused while the ad is open; back while
  the revive ad is open is ignored; back during the 500 ms crash beat saves
  the run once and no revive offer appears afterwards; leaving by back
  (before the first tap, and from results) restores edge-to-edge; taps on
  PLAY AGAIN inside the 400 ms lock don't restart and a tap after it does;
  the results upgrade shortcut shows when crystals equal the cost exactly
  and hides one crystal short; haptics per event (shield = one medium,
  near miss = light with max one per 300 ms, none on thrust or crystals)
  and the off switch silencing crash, shield and near miss. Mutation
  checks: 19 guards broken one at a time in `lib/`; before this change 4
  survived (near-miss haptic throttle, shield haptic, countdown pause
  during the ad, floor drawing); the new tests kill the first 3 (floor
  drawing is visual: device checklist). No product code changed.
- **Why:** QA verification of PR #3 (UX PR 1): these failure paths were
  not covered, so the features could break without a red test.
- **Agent:** qa-engineer
- **Files:** `test/qa_failure_paths_test.dart` (new)
- **Refs:** AJ_PROBE `ux-plan.md` PR 1 #1–#6, #10; `ux-review.md` A-01, A-06, A-07, A-08, A-18, A-29; #0008–#0013, #0017

## #0020 — 2026-10-09 — CHANGE — Strong, per-event haptics through the vibration motor (S26 checks 1, 8; A-29)
- **What:** Game haptics on Android now go through a new
  `probe_dash/haptics` platform channel in `MainActivity.kt`, which drives
  the motor with `VibratorManager` (API 31+) / `Vibrator` (older):
  `createOneShot` / `createWaveform` on API 26+ (amplitude falls back to
  the default when the phone has no amplitude control), the legacy
  pattern `vibrate` on API 24–25, and nothing when `hasVibrator()` is
  false. Added the `VIBRATE` permission. Length and strength per event
  live in Dart (`Haptics.patterns`, unit-tested): crash 80 ms at 255
  (the only full-strength buzz), shield 40 ms at 170, near miss 20 ms at
  110, new best a double pulse 35 + 35 ms at 170, upgrade buy 20 ms at
  110. Closed A-29's gaps: `Haptics.newBest()` fires on
  `RunEvent.newBest`, and `Haptics.upgradeBought()` fires on a successful
  buy in the Upgrades screen (on the tap, not after the save).
  `Haptics.enabled` and the static API are unchanged; the backend is
  injectable (`Haptics.backend`) so tests record which event fired which
  haptic. Channel errors (`PlatformException`, `MissingPluginException`)
  are swallowed. iOS keeps Flutter's `HapticFeedback` calls. Existing
  haptic tests now assert on the new channel / recorder (same
  expectations: crash once, shield once, near miss throttled, none for
  thrust or crystals, switch off silences all); new `test/haptics_test.dart`
  (15 tests).
- **Why:** Owner's S26 run of build 15 failed check 1 (crash "one strong
  buzz") and check 8 (haptics per event) with touch vibration on. Root
  cause: on Android Flutter's `heavyImpact`/`mediumImpact`/`lightImpact`
  call `View.performHapticFeedback` with `CONTEXT_CLICK` / `KEYBOARD_TAP` /
  `VIRTUAL_KEY` (Flutter engine `PlatformPlugin.vibrateHapticFeedback`).
  These are short UI clicks tuned by the phone maker; One UI plays them as
  faint, near-identical ticks, so there was no strong crash buzz and no
  felt difference between events. Predefined effects (`EFFECT_HEAVY_CLICK`
  etc.) were not used for the same reason: their strength is also
  maker-tuned.
- **Agent:** engineer
- **Files:** `lib/game/haptics.dart`, `lib/game/probe_game.dart`,
  `lib/ui/upgrades_screen.dart`,
  `android/app/src/main/kotlin/com/southicarus/probe_dash/MainActivity.kt`,
  `android/app/src/main/AndroidManifest.xml`, `test/haptics_test.dart`
  (new), `test/support/fakes.dart`, `test/game_screen_test.dart`,
  `test/qa_failure_paths_test.dart`
- **Refs:** AJ_PROBE `qa/pr3-device-checklist.md` checks 1, 8;
  `ux-review.md` A-29; spec FEEL-07; #0019

## #0021 — 2026-10-09 — CHANGE — Upgrade shortcut on one line, font-safe results card, buys never blocked by a stuck save (S26 check 13; A-18, A-22, A-27)
- **What:** (1) The results shortcut label is now
  "Upgrade: Crystal Value Lv1 – 100 ◆" (was "Upgrade ready: …"), on one
  line: it fits 360 dp at normal font size and scales down instead of
  wrapping when it doesn't (`UpgradeOffer.label`, max 36 characters,
  unit-tested). (2) The revive / results card (`_Panel`) clamps text to
  1.3× and scrolls when taller than the screen (A-27); outer margin
  24 → 16 dp and card padding 24 → 20 dp; the "Upgrades · Home" row wraps
  instead of overflowing. (3) `GameController.buyUpgrade` still ignores a
  buy while the previous one is saving (A-22), but waits at most 2 s
  (`buySaveWaitLimit`) for that save, so a save that never finishes can't
  block every later buy. New `test/phone_size_test.dart` runs at S26 sizes
  (1080 × 2340 px at DPR 2.63 → 411 × 891 dp and DPR 3 → 360 × 780 dp,
  84 px camera inset): shortcut on one line, fully on screen, hittable
  and opens Upgrades; "Upgrades" button opens Upgrades and back returns;
  every Buy button hittable and a fast double tap buys one level; 2× font
  has no overflow and buttons stay reachable; the A-27 800 × 360 at 2×
  case; and a stuck save. Existing shortcut tests updated to the new label.
- **Why:** Owner's S26 check 13: "cannot click upgrade". **Not
  reproduced.** At S26 sizes the old shortcut was on screen, hittable and
  opened Upgrades, and Buy worked (these tests pass against the old
  layout at 1× and 1.3× font). Andy's web build of main at 412 × 915 agreed
  (shortcut opened Upgrades; double tap bought one level) and saw the
  label wrap so "◆" sat alone on a second line. Ruled out by reading the
  code: `SaveStore.save` catches every error, so a save only hangs if
  file IO itself hangs (now capped anyway); `immersiveSticky` passes
  taps through to the app (only edge swipes reveal the bars); the 400 ms
  entry lock and tile lock clear on timers. Found and fixed: at large
  system font (2×) the old card overflowed, leaving the shortcut and
  "Upgrades / Home" drawn outside the card where taps don't reach them
  (3 of the new tests fail against the old layout), plus the wrapped
  label Andy reported.
- **Agent:** engineer
- **Files:** `lib/ui/game_screen.dart`, `lib/logic/upgrades.dart`,
  `lib/app/game_controller.dart`, `test/phone_size_test.dart` (new),
  `test/logic/upgrades_test.dart`, `test/game_screen_test.dart`,
  `test/qa_failure_paths_test.dart`
- **Refs:** AJ_PROBE `qa/pr3-device-checklist.md` check 13 (its expected
  label text changes); `ux-review.md` A-18, A-22, A-27; #0017

## #0022 — 2026-10-09 — NOTE — S26 check 9 "no new best": logic verified, not reproduced
- **What:** Verified best / NEW BEST end to end at S26 sizes in
  `test/phone_size_test.dart`: first run ever (best 0) gives no banner or
  haptic by design and results say "NEW BEST!"; PLAY AGAIN on the same
  game carries the new best ("BEST 60 m"), the gold line is on screen
  ahead of the probe 10 m before it, passing it fires one `newBest`
  (banner at full opacity, centred inside the screen below the HUD; HUD
  line "NEW BEST"; one new-best haptic) and results say "NEW BEST!"; Home
  → PLAY starts a game with the saved best; a run equal to the best is
  not a new best in the run or on results (both use the floored meters).
  Added small test hooks in `ProbeGame` (`bestMarkerX`,
  `bestMarkerWorldX`, `newBestBannerAnchor`) that the drawing code now
  uses, so the tests check the same numbers that are drawn.
- **Why:** Owner reported check 9 "no new best". No code fault found;
  Andy's web build at 412 × 915 also showed the HUD switch and the banner.
  Likely test condition: the best carried over from earlier builds
  (installing over keeps the save) was higher than the runs played, or
  the first run after a fresh install (best 0, no banner by design).
  Owner to recheck with Home → "Best: N m" noted first and a run past N.
- **Agent:** engineer
- **Files:** `lib/game/probe_game.dart`, `test/phone_size_test.dart`
- **Refs:** AJ_PROBE `qa/pr3-device-checklist.md` check 9; `ux-review.md`
  A-04; #0018

## #0023 — 2026-10-09 — CHANGE — Pure interstitial rule for spec v2 (plan step A-1)
- **What:** New `lib/logic/ad_rules.dart` with `InterstitialRule.decide`,
  the spec v2 §3.3 decision in its order: (a) `remove_ads`, (b) lifetime
  runs > 3 and a multiple of 3, (c) 90 s gap, (d) rewarded ad this run →
  `skippedRewarded`, (e) loaded and younger than 1 h → else `notLoaded`;
  all met → `show`. A `lastInterstitialAt` in the future (clock moved
  back) counts as absent (AD-9; fixes plan bug A3, which blocked the ad).
  `AdPolicy` is removed from `progress.dart` (a class inside a file, so no
  archive), and its 4 tests are replaced by `test/logic/ad_rules_test.dart`
  (26 tests covering the same cases plus the new ones). The old
  leave-Results call in `GameController.maybeShowInterstitial` uses the
  new rule until plan step A-3 removes it.
- **Why:** Spec v2 (approved at G1, OD-3 to OD-7 yes) moves the
  interstitial to Results-open and adds AD-5 to AD-9; the tech lead's plan
  puts the rule in pure Dart so `flutter test` covers every branch.
- **Agent:** engineer
- **Files:** `lib/logic/ad_rules.dart` (new), `lib/logic/progress.dart`,
  `lib/app/game_controller.dart`, `test/logic/ad_rules_test.dart` (new),
  `test/logic/progress_test.dart`
- **Refs:** spec v2 AD-5 to AD-9, §3.3; AJ_PROBE
  `tech/plan-spec-v2-ads-analytics.md` step A-1, bug A3

## #0024 — 2026-10-09 — CHANGE — Ad service reports how each ad ended (plan step A-2)
- **What:** `AdService.showRewarded()` now returns `RewardedOutcome`
  (`earned`, `closedEarly`, `failedToShow`, `notLoaded`) instead of a
  bool, so "closed early" (shown, counts for AD-6) is no longer the same
  as "failed to show" (not shown). The reward is still granted only for
  `earned` (US-1). The interstitial gets a monotonic load `Stopwatch` and
  `interstitialAge` (AD-7 expiry), `requestInterstitialLoad()` and
  `discardStaleInterstitial()`, and a `_loadingInterstitial` flag so two
  loads never run at once. `showInterstitial` takes `onShown`,
  `onFailed` and `onDismissed` callbacks and returns at once; the ad is
  disposed only on dismiss or failure, because the SDK can't cancel a
  show already requested and a disposed ad's later callbacks are dropped.
  Callers (`GameController`, `GameScreen`, `FakeAds`, the QA `HeldAds`
  fake) are moved to the new types; the interim leave-Results call now
  counts the ad when it appears. No behaviour change for players yet.
- **Why:** Plan bugs A5 and A6: AD-6 needs "shown" vs "failed" and AD-7
  needs the ad's age; AD-9 needs the moment the ad appears.
- **Agent:** engineer
- **Files:** `lib/services/ad_service.dart`, `lib/app/game_controller.dart`,
  `lib/ui/game_screen.dart`, `test/support/fakes.dart`,
  `test/qa_failure_paths_test.dart`
- **Refs:** spec v2 AD-6, AD-7, AD-9, US-1; plan step A-2, bugs A5, A6

## #0025 — 2026-10-09 — CHANGE — Interstitial at Results-open in the controller (plan step A-3)
- **What:** New `GameController.openResults(result)`: applies the run
  (`stats.runs += 1`), queues its save, runs `InterstitialRule.decide` and
  returns `ResultsOpen` (`newBest`, `decision`, `locked`, `unlocked`). On
  `show` the ad is requested only after the run save finishes (AD-5);
  `unlocked` completes on dismiss, on failure, or 2 s after Results-open
  if the ad hasn't appeared (AD-8); it stays locked while an ad that
  appeared in time is on screen. `lastInterstitialAt` and
  `interstitialsShown` are set and saved in `onShown` (AD-9; fixes bug
  A2). `notLoaded` requests a load (or discards an ad older than 1 h)
  and never shows it later in that run cycle (AD-7). New
  `showReviveAd()` marks the run on `earned` or `closedEarly`, not on
  `failedToShow` (AD-6); `runStarted()` clears the mark; a token revive
  never sets it. New `clock` constructor parameter for tests.
  **Late ads (decision S2):** the SDK can't cancel a requested show, so
  the design keeps it harmless and provable: (1) the show is requested
  only while the lock is on; if the save takes the whole 2 s the ad is
  not requested at all; (2) a late `onShown` counts and saves like any
  shown ad (AD-9), is tallied in `lateInterstitials`, and never re-locks
  or changes the screen (`unlocked` completes once); (3) a new
  `interstitialOnScreen` listenable is true while any interstitial is up,
  which the game screen uses (step A-4) to freeze the engine, so a late
  ad can't cover a moving run. `completeRun` and `maybeShowInterstitial`
  stay until A-4 moves the screen over. `FakeAds` gets a scriptable
  interstitial (`InterstitialScript`: appears after, fails, dismiss
  after; manual appear/dismiss/fail), counters and a shared order log;
  `InstantStore` records each save as written (`onDisk` = what an app
  kill leaves); `makeController` takes runs, remove_ads, last shown and
  a clock. New `test/interstitial_controller_test.dart` (21 tests).
- **Why:** Spec v2 AD-5 to AD-9 and US-5 failure paths; plan step A-3
  and risk R1 / spec issue S2 (Andy asked for a provable late-ad design).
- **Agent:** engineer
- **Files:** `lib/app/game_controller.dart`, `test/support/fakes.dart`,
  `test/interstitial_controller_test.dart` (new)
- **Refs:** spec v2 AD-5 to AD-9, US-5, §3.3, §7; plan step A-3, bugs A2,
  R1, S2; #0023, #0024

## #0026 — 2026-10-09 — CHANGE — Results lock and no ad on Play again / Home (plan step A-4)
- **What:** `GameScreen` calls `openResults` when Results opens and
  locks Results until `unlocked` (AD-8): Play again, Home, Upgrades, the
  upgrade shortcut and 2× show as disabled, and the back gesture is
  ignored (`PopScope.canPop` is false while locked; fixes bug A4). After
  the lock, back goes Home with no ad. `_leaveResults` no longer calls
  the interstitial and is synchronous (fixes bug A1: Play again and Home
  showed the ad; GAME-4). The revive button goes through
  `GameController.showReviveAd` (AD-6); each new run calls `runStarted`.
  `GameController.completeRun` and `maybeShowInterstitial` are removed
  (no callers left). **Late-ad guard (decision S2):** while
  `interstitialOnScreen` is true the screen pauses the Flame engine and
  ignores taps (the revive countdown also pauses), then resumes it when
  the ad closes, the same as returning from the background. So a late ad
  that the SDK shows after Play again can't cover a moving run: no
  physics, crash or score happen under it; it is counted (AD-9); the
  screen doesn't change. New `test/interstitial_flow_test.dart` (18
  widget tests): lock, 5 taps and back ignored, back inside the ad lands
  on Results, one tap to Ready in < 1 s, 2 s timeout, failure, Play
  again / Home / back never show an ad (runs 6 to 12 and the old A1
  case), revive watched / closed early / failed, not loaded, remove_ads,
  late ad during play / after Home / on Results, app kill during the ad.
  Mutation-checked: dropping the lock, the back block, the freeze, or
  adding an ad on leave each fails at least one test.
- **Why:** Spec v2 AD-1, AD-5 to AD-9, GAME-4, §8 ResultsScreen states,
  US-5; plan step A-4; Andy's S2 instruction that a late ad must be
  harmless and provably never over gameplay.
- **Agent:** engineer
- **Files:** `lib/ui/game_screen.dart`, `lib/app/game_controller.dart`,
  `test/interstitial_flow_test.dart` (new)
- **Refs:** spec v2 AD-1, AD-5 to AD-9, GAME-4, US-5, §7, §8; plan step
  A-4, bugs A1, A4, R1, S2; #0025

## #0027 — 2026-10-09 — CHANGE — Build environment config and AD-3 runtime fallback (PR F, step 1)
- **What:** New pure-Dart `lib/config/env.dart` (`EnvConfig`, `Flavor`)
  reads the compile-time defines `FLAVOR`, `ADS_MODE`, `ANALYTICS`,
  `BUILD_LABEL`, `DEBUG_MENU`, `ADMOB_REWARDED_ID`,
  `ADMOB_INTERSTITIAL_ID`, plus Flutter's own `FLUTTER_APP_FLAVOR`,
  `FLUTTER_BUILD_NAME` and `FLUTTER_BUILD_NUMBER`. With no defines
  (`flutter test`, a bare local run) it defaults to flavor dev, Google
  test ad units and analytics off. **Runtime fallback (AD-3, ENV-3):**
  real ad unit IDs are used only when the config says `prod`, the Gradle
  flavor is also `prod`, `ADS_MODE` is `real`, the platform is Android and
  the ID is a well-formed AdMob unit ID; every other case gets the Google
  test unit, so dev and beta can never get a real ID. Analytics is
  allowed only in matching beta/prod builds with `ANALYTICS=on` (AN-6;
  used from PR B). Debug menu flag is dev-only (ENV-9; no menu exists
  yet). New non-secret `config/dev.json`, `config/beta.json`,
  `config/prod.json` and `config/README.md`. `AdService` now takes its
  unit IDs from `EnvConfig` instead of hard-coded test IDs. Home shows
  the build label by flavor (UI-2 as amended in spec v3): dev "DEV ·
  test ads" + version, beta "BETA X.Y.Z (N)", prod none; it replaces the
  "Prototype · test ads only" line. 25 new tests: `test/config/env_test.dart`
  (defaults, ID validation, every flavor × Gradle flavor × mode × platform
  combination for dev/beta, label, analytics, debug menu) and 2 widget
  tests in `test/widget_test.dart`. Test files build their fake "real" ID
  at runtime so no real-looking ID is committed.
- **Why:** environments.md §4 and §5 PR F step 4–5; spec v3 AD-3, AN-6,
  OPS-1, UI-2; security review SEC-21 (runtime fallback when FLAVOR ≠
  prod). Flavor decided by both the config and the Gradle flavor so a
  mixed-up build is treated as not prod.
- **Agent:** engineer
- **Files:** `lib/config/env.dart` (new), `config/dev.json`,
  `config/beta.json`, `config/prod.json`, `config/README.md` (new),
  `lib/services/ad_service.dart`, `lib/ui/home_screen.dart`,
  `test/config/env_test.dart` (new), `test/widget_test.dart`
- **Refs:** spec v3 AD-3, AN-6, OPS-1, OPS-2, UI-2, US-13;
  environments.md §4, §5 PR F; SEC-21; ENV-D2, ENV-D3

## #0028 — 2026-10-09 — CHANGE — CLAUDE.md points at the latest approved spec (spec.v3.md)
- **What:** `CLAUDE.md` §0 said the source of truth is
  `docs/products/probe-dash/spec.md`. It now says the latest approved
  version in `docs/products/probe-dash/` of AJ_PROBE, currently
  `spec.v3.md` (approved at G1, AJ_PROBE #0061). Small in-place edit
  (rule 4 allows it for small fixes).
- **Why:** Audy's audit (R-2 / P-1), relayed by Andy: agents reading
  CLAUDE.md were pointed at the superseded v1 spec.
- **Agent:** engineer
- **Files:** `CLAUDE.md`
- **Refs:** AJ_PROBE #0055, #0061

## #0029 — 2026-10-09 — CHANGE — Android flavors dev / beta / prod, DEV icon, .gitignore for secrets (PR F, step 2)
- **What:** `android/app/build.gradle.kts` adds the `env` flavor
  dimension: **dev** (`applicationIdSuffix ".dev"` →
  `com.southicarus.probe_dash.dev`, `versionNameSuffix "-dev"`, always the
  debug key so `dev-N` APKs update in place), **beta** and **prod** (both
  the locked Play ID `com.southicarus.probe_dash`, ENV-D1). The AdMob app
  ID is a manifest placeholder: Google's test app ID in dev and beta; prod
  uses env `ADMOB_APP_ID` only if release.yml sets it, else the test ID.
  beta/prod sign with an `upload` signing config read from env
  `UPLOAD_KEYSTORE_PATH`, `UPLOAD_KEYSTORE_PASSWORD`, `UPLOAD_KEY_ALIAS`,
  `UPLOAD_KEY_PASSWORD`; without them they fall back to the debug key
  (Play rejects it; release.yml refuses it). The release build type no
  longer sets a signing config, because a build type's config would
  override the flavor's. The manifest label is `@string/app_name`:
  "Probe Dash" (`src/main/res/values/strings.xml`), "Probe Dash Dev"
  (`src/dev/res/values/strings.xml`). The dev flavor has its own launcher
  icon: the current icon with an orange **DEV** ribbon
  (`src/dev/res/mipmap-*/ic_launcher.png`, generated from the main icons).
  `pubspec.yaml`: version `0.1.0+1` (plan step 6) and
  `default-flavor: dev`, so a bare `flutter run` / `flutter build apk`
  builds dev (verified in the Flutter 3.47.6 tool source; it affects iOS
  too, which has no flavor schemes yet). Root `.gitignore` adds `*.jks`,
  `*.keystore`, `key.properties`, `google-services.json`,
  `**/GoogleService-Info.plist`, `*.p12`, `*.pem`, `*.base64`, `*.b64`,
  `.env*`, `config/*.secrets.json` (SEC-12). README: environments table,
  dev install steps, flavor run/build commands.
- **Owner note:** the dev app is a **new app** on the phone ("Probe Dash
  Dev", `.dev` ID). It installs **next to** the old "Probe Dash"
  prototype from `proto-N`; progress does not carry over. The old
  prototype must be uninstalled before the Play build is installed
  (ENV-R8).
- **Why:** environments.md §5 PR F steps 1–3, 6, 7; spec v3 OPS-1, ENV-7;
  security review SEC-9 (dev builds can no longer install over Play
  builds), SEC-12.
- **Not verified:** no Android SDK in this session (dl.google.com is
  blocked by the egress proxy), so the Gradle changes were not built
  locally; CI's `Build` and `Launch test` are the first build.
- **Agent:** engineer
- **Files:** `android/app/build.gradle.kts`,
  `android/app/src/main/AndroidManifest.xml`,
  `android/app/src/main/res/values/strings.xml` (new),
  `android/app/src/dev/res/values/strings.xml` (new),
  `android/app/src/dev/res/mipmap-*/ic_launcher.png` (new, 5 files),
  `pubspec.yaml`, `.gitignore`, `README.md`
- **Refs:** spec v3 OPS-1, AD-3, US-13; ENV-D1, ENV-D2, ENV-7, ENV-R8;
  SEC-9, SEC-12; #0027

## #0030 — 2026-10-09 — CHANGE — Secrets guard, APK guard scripts, Repo rules hardening (PR F, step 3)
- **What:** Three guard scripts (Python 3 standard library only, each
  with a `--self-test`):
  - `.github/scripts/check_ad_ids.py`: `repo` mode fails if any tracked
    file holds an AdMob ID (`ca-app-pub-<16 digits>` + `~` or `/`) whose
    publisher is not Google's test publisher `3940256099942544`, or if a
    `*.jks`, `*.keystore`, `key.properties`, `google-services.json`,
    `GoogleService-Info.plist`, `*.p12`, `*.pem`, `*.base64`, `*.b64`,
    `.env*` or `*.secrets.json` file is tracked. `artifact` mode scans a
    built APK/AAB (every entry, nested zips, UTF-8 and UTF-16LE):
    `--expect test` fails on any non-test publisher or on no ID at all;
    `--expect real` (prod with secrets) requires a non-test app ID and a
    non-test unit ID. IDs are printed masked.
  - `.github/scripts/check_permissions.py`: compares the permissions in
    `aapt2 dump badging` with the committed allow-list
    `.github/android-permissions.txt` (own package written as
    `${applicationId}`); fails on any addition or removal and prints the
    actual list.
  - `.github/scripts/check_16kb.py`: every 64-bit `.so` must have ELF
    `PT_LOAD` alignment ≥ 16 KB, and in an APK a stored `.so` must sit at
    a 16 KB zip offset.
  `repo-rules.yml`: new job **"Secrets guard (no real AdMob IDs or
  signing files)"** runs the self-tests and the repo scan on every push
  and PR. The existing job keeps its name; its checkout is pinned to a
  commit SHA with `persist-credentials: false`, and the force-push
  message takes the branch name from `env:` instead of
  `${{ github.ref_name }}` inside `run:`.
- **Why:** security review SEC-13 (script injection), SEC-3 / CI-4 / CI-5
  (pins, no persisted token), SEC-21 / CI-10 / ENV-4 (repo guard),
  SEC-6 / SEC-20 / REL-3 (permission allow-list), F8 / ENV-12 / REL-2
  (16 KB). Python avoids needing aapt2 or zipalign for the ID and 16 KB
  checks.
- **Not verified:** the allow-list is written from SDK knowledge, not from
  a build (no Android SDK here; Maven/dl.google.com blocked). Unconfirmed
  entries: the three AdServices permissions, `WAKE_LOCK`,
  `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE` and
  `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. The first `Build` run
  prints the real list; if it differs, `Build` fails until the list is
  reconciled in a reviewed commit. Verified locally: all self-tests pass;
  the repo scan passes on this tree and fails on a staged file with a
  fake non-test ID; `actionlint` passes.
- **Agent:** engineer
- **Files:** `.github/scripts/check_ad_ids.py`,
  `.github/scripts/check_permissions.py`, `.github/scripts/check_16kb.py`,
  `.github/android-permissions.txt` (all new),
  `.github/workflows/repo-rules.yml`
- **Refs:** SEC-3, SEC-6, SEC-13, SEC-20, SEC-21; CI-4, CI-5, CI-6,
  CI-10; REL-2, REL-3; ENV-4, ENV-12; #0027, #0029

## #0031 — 2026-10-09 — CHANGE — Build and Launch test move to the dev/beta flavors; dev-N pre-releases; CI hardening (PR F, step 4)
- **What:**
  - **`build.yml`** (workflow name `Build`; job names "Analyze and
    test" and "Build APK" unchanged): builds `flutter build apk --release
    --flavor dev --dart-define-from-file=config/dev.json` on every push
    and PR, then runs the new `.github/scripts/check-apk.sh` (package
    `com.southicarus.probe_dash.dev`, targetSdk ≥ 36, versionCode = run
    number, permission allow-list, 16 KB, test ad IDs only). Publishing
    moved to a new job **"Publish dev pre-release"**: only on push to
    `main`, `contents: write`, no checkout or build steps, it downloads
    the artifact and creates release **`dev-<run>`** ("Dev build N",
    `probe-dash-dev-N.apk`). It replaces `proto-<run>`; old `proto-*`
    releases are untouched. The build jobs are `contents: read`. The
    debug-key cache (same key as before, `prototype-debug-keystore-v1`)
    is restored and saved only on push to `main`; PR builds sign with a
    throwaway key Gradle generates.
  - **`launch-test.yml`** (name `Launch test`): a matrix of dev on API
    30/35/36 (check names unchanged: "Opens without crashing (Android
    API N)") plus **beta on API 36** ("Opens without crashing (beta,
    Android API 36)", `com.southicarus.probe_dash`). Builds use the
    flavor's config with `--dart-define=ANALYTICS=off` (a `--dart-define`
    wins over the file, checked in the Flutter 3.47.6 tool source).
  - All workflows: every action pinned to a full commit SHA with a
    version comment (latest release of each, all on the Node 24
    runtime), `persist-credentials: false` on every checkout, `flutter
    pub get --enforce-lockfile` before analyze/test/build.
  - New **`.github/dependabot.yml`**: weekly `github-actions` (grouped)
    and `pub` updates.
- **Owner note:** the next `main` build publishes **`dev-N`**, not
  `proto-N`. It installs as a **new app, "Probe Dash Dev"**, next to the
  old prototype; prototype progress does not carry over. Required-check
  names: the existing ones are kept; the new checks are "Secrets guard
  (no real AdMob IDs or signing files)", "Opens without crashing (beta,
  Android API 36)" and "Publish dev pre-release" (main only).
- **Why:** environments.md §5 steps 9–15; security review SEC-3, SEC-9,
  SEC-14, CI-3 to CI-5, CI-8, CI-9; spec v3 US-13 ("Probe Dash Dev"
  installs next to the Play app).
- **Not verified:** CI-only. The first flavored build, the APK guards
  (including the unconfirmed permission entries, #0030) and the emulator
  runs happen on the first push. `subosito/flutter-action` v2.23.0 is a
  composite action that itself uses `actions/cache@v5` by tag (not
  pinnable from here). `distributionSha256Sum` for the Gradle wrapper
  (SEC-14) was **skipped**: the official checksum on services.gradle.org
  could not be fetched (egress proxy 403), so it could not be verified.
  Verified locally: `actionlint`, YAML parse, `shellcheck`.
- **Agent:** engineer
- **Files:** `.github/workflows/build.yml`,
  `.github/workflows/launch-test.yml`, `.github/scripts/check-apk.sh`
  (new), `.github/dependabot.yml` (new)
- **Refs:** SEC-3, SEC-9, SEC-14; CI-3, CI-4, CI-5, CI-8, CI-9; ENV-R10;
  spec v3 US-13, AN-6; #0029, #0030

## #0032 — 2026-10-09 — CHANGE — release.yml: tag-triggered beta/prod builds, dry run by default, never uploads to Play (PR F, step 5)
- **What:** New `.github/workflows/release.yml` ("Release"), triggered by
  tags `beta-v*` / `v*` and by `workflow_dispatch` (a rehearsal with a
  tag name input). Jobs:
  - **verify** (`.github/scripts/release-verify.sh`): tag matches
    `^(beta-)?vX.Y.Z+N$`; `X.Y.Z` equals `pubspec.yaml`; N is greater than
    every other `beta-v*`/`v*` tag; the commit is on `main`; the latest
    `Repo rules`, `Build` and `Launch test` push runs on `main` for that
    commit succeeded; a prod tag has a `beta-v*` tag on the same commit.
    On a tag push all are errors; in a manual rehearsal the last three
    are warnings.
  - **test**: analyze + test.
  - **build-dry-run** (default) or **build-signed**
    (`.github/scripts/release-build.sh`): AAB + universal APK with
    `--flavor <beta|prod> --dart-define-from-file=config/<flavor>.json
    --build-name X.Y.Z --build-number N`. The dry run signs with a
    throwaway key made on the runner ("CN=NOT FOR UPLOAD"), uses test ad
    IDs and names everything `…-NOT-FOR-UPLOAD`. **Only `build-signed`
    declares `environment: play-release`** and reads `UPLOAD_*` and (prod
    only) `ADMOB_*` secrets, through `env:` only, written to
    `$RUNNER_TEMP` and deleted in an `if: always()` step. Real ad unit IDs
    go in as a second `--dart-define-from-file` in `$RUNNER_TEMP`, not on
    the command line.
  - **guards**: SHA-256 check; AAB (`.github/scripts/check-aab.sh`) not
    debug-signed and signed at all, 16 KB, ad IDs; universal APK
    (`check-apk.sh`) package, versionCode = N, targetSdk ≥ 36,
    permission allow-list, 16 KB, ad IDs.
  - **launch**: the emulator launch test on API 30/35/36 with the
    universal APK.
  - **publish**: only for a tag push in signed mode after all of the
    above; `contents: write`; downloads the artifact and attaches the
    **AAB and its SHA-256 only** (pre-release for beta, release for
    prod). The R8 mapping is a workflow artifact (90 days signed, 30 days
    dry run), never on the release. Nothing is sent to Play.
- **Decision needed (owner):** how a tag push leaves dry-run mode. I used
  a **repository variable** `PLAY_RELEASE_ENABLED=true` (a variable, not
  a secret). Until the owner sets it, every tag push is a dry run.
  Recommendation: set it only after creating `play-release` (tags `v*`,
  `beta-v*`; owner as required reviewer) and its secrets.
- **Deviation (note):** environments.md §5 step 20 says a prod build must
  not contain the test publisher ID at all. That can't hold: the AD-3
  runtime fallback (#0027) compiles the test IDs into every build. The
  prod guard instead requires a real app ID **and** a real unit ID to be
  present; dev/beta/dry runs require test IDs only.
- **Not done here:** `GOOGLE_SERVICES_JSON` is not written yet (no
  Firebase in the app; PR B adds it in `build-signed` only).
- **Why:** environments.md §5 steps 16–23; spec v3 OPS-2, OPS-6, US-13;
  security review SEC-1, SEC-3, SEC-15, CI-1 to CI-3, CI-13, REL-2,
  REL-3, REL-4.
- **Not verified:** CI-only. Verified locally: `actionlint`, YAML parse,
  `shellcheck`; `release-verify.sh` rehearsed for good tags, a bad
  format, an injection-style tag, a pubspec mismatch, a build number that
  doesn't increase and the prod beta-tag rule (in a scratch clone).
  Whether a tag created in the GitHub web UI triggers `push: tags`, and
  how GitHub treats `environment: play-release` before the owner creates
  it (it may auto-create it unprotected; only signed mode uses it), are
  not verified.
- **Agent:** engineer
- **Files:** `.github/workflows/release.yml`,
  `.github/scripts/release-verify.sh`, `.github/scripts/release-build.sh`,
  `.github/scripts/check-aab.sh` (all new)
- **Refs:** SEC-1, SEC-3, SEC-15; CI-1, CI-2, CI-3, CI-13; REL-2, REL-3,
  REL-4; ENV-1, ENV-2, ENV-5, ENV-6, ENV-10, ENV-12; #0029, #0030, #0031

## #0033 — 2026-10-09 — NOTE — Correction to #0027: 23 new tests, not 25
- **What:** #0027 says PR F step 1 added 25 tests. The real number is
  **23**: 21 in `test/config/env_test.dart` and 2 widget tests in
  `test/widget_test.dart`. The suite goes from 180 to 203 tests, all
  passing.
- **Why:** Keep the record accurate (rule 2: correct with a new entry).
- **Agent:** engineer
- **Files:** none
- **Refs:** #0027

## #0034 — 2026-10-09 — CHANGE — Reconcile APK guards with the first flavored CI build
- **What:** The first `Build` run of PR #6 (run 37922551104,
  `probe-dash-dev-23.apk`) compiled all flavors. The APK guards failed
  for two reasons:
  1. **Permission allow-list** (`.github/android-permissions.txt`): two
     guessed entries were not in the real APK and were removed:
     `RECEIVE_BOOT_COMPLETED` and the declared
     `permission ${applicationId}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
     (only the `uses-permission` line exists). The list now matches the
     10 entries the build printed exactly.
  2. **Ad-ID guard** (`check_ad_ids.py`): a `ca-app-pub-0000000000000000~…`
     **placeholder** is compiled into a dependency's `classes.dex`; it is
     not in our sources (grep). An all-zero publisher names no AdMob
     account, so it can't serve ads or earn. In built artifacts it is now
     printed as "placeholder (ignored)" and never counts as a real ID
     (prod still needs a real app ID and unit ID). The repo scan stays
     strict. Two self-test cases were added; all self-tests pass.
- **Why:** The allow-list was written before any Android build existed
  (#0030 said the first build would confirm it). The guard must flag
  real IDs, not the SDK's placeholder.
- **Files:** .github/android-permissions.txt, .github/scripts/check_ad_ids.py

## #0035 — 2026-10-09 — CHANGE — Extra agent safety rules in .claude/settings.json (SEC-16)
- **What:** Added 15 deny rules for Claude sessions in this repo: no
  `git push --force-with-lease`, `--delete` or `+` refspecs, no
  `git reset --hard`, `git branch -D` or `git tag`, no `gh release`,
  `gh secret` or `gh pr merge`, no `printenv`/`env`, and no reading
  `*.jks`, `*.keystore`, `key.properties` or `google-services.json`.
- **Why:** The owner approved security finding SEC-16 (AJ_PROBE #0073).
  These are speed bumps; GitHub rulesets remain the real control.
- **Files:** .claude/settings.json
