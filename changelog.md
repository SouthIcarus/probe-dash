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
