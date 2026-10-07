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
