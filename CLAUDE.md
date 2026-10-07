# Probe Dash — Claude Working Rules

These rules apply to every Claude session on this repository. They are
**hard rules**: follow them on every change, without being reminded.

## 0. Project context

Probe Dash is a hybrid-casual mobile game: Flappy-style one-tap flying
through asteroid gaps, plus crystals that buy upgrades and skins, with ads
and small in-app purchases. It is the first product of the owner's
AJ_PROBE toolkit.

- **The spec is the source of truth:** `docs/products/probe-dash/spec.md`
  in the `SouthIcarus/AJ_PROBE` repo. Requirement IDs in code comments and
  changelog entries (GAME-1, IAP-3, AD-1, ...) refer to that spec.
- **Stack:** Flutter + Flame (Dart). Game rules live in `lib/logic/` as
  pure Dart with no Flutter imports, so `flutter test` covers them.
- **Ads:** only Google's test ad unit IDs until the owner says otherwise
  (spec AD-3). Never commit real AdMob IDs together with code that clicks
  or auto-shows ads.
- **No secrets in the repo:** signing keys, keystore passwords, and API
  keys go in GitHub Actions secrets or environment settings only.
- The owner is a Sr. IT BA / Product Owner: lead with a TL;DR, use tables,
  and say plainly what was and wasn't verified.

## 1. Log every decision and note in `changelog.md`

- Every decision, note, change, blocker, or learning **shall** be recorded
  as a new entry in `changelog.md`, in the **same commit** as the change.
- Every entry **shall** state *what* happened and *why*.

## 2. `changelog.md` is append-only

- New entries go at the **bottom** only. Existing entries are never
  edited, reordered, or deleted; correct one with a new entry that
  references it ("Supersedes #0004").

## 3. No deletion of core files

Every committed file is core, except generated output tooling rebuilds
(build output, `.dart_tool/`, lockfiles).

- Retire a file by moving it to `archive/` with a `DEPRECATE` entry.
- True deletion needs the owner's approval first and a `DELETE` entry.

## 4. Version documents instead of overwriting them

Substantially rewritten documents get a new `name.vN.md` file. Code is
versioned by git history.

## 5. Never

- Never force-push or rewrite pushed history.
- Never put secrets in any committed file.

## 6. Checks before every push

```bash
flutter analyze
flutter test
bash .github/scripts/check-repo-rules.sh origin/main HEAD
```
The `Repo rules` and `Build` GitHub checks run the same on every push and PR.
