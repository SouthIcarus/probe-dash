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
