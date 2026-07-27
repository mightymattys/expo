# Changelog

expo is a fork of [sous-chef](https://github.com/tomascupr/sous-chef) by Tomas Cupr
(MIT). Versions before 0.6.0 are sous-chef history; the fork begins at 0.6.0.

## 0.7.12 - 2026-07-27

- `scripts/release.sh` stamps the changelog inside the release commit: the
  `## Unreleased` heading becomes `## <version> - <UTC date>`, keeping any title, and
  a release with no entry - or an entry naming a different version - is refused. Both
  0.7.9 and 0.7.10 shipped still labelled "Unreleased" because this was a manual step.
  A failed stamp restores the changelog alongside the version bump.
- CI asserts every changelog heading carries a date and that at most one Unreleased
  heading exists.

## 0.7.11 - 2026-07-27 - the benchmark harness

- `scripts/bench.sh`: a reporter over a human-recorded JSONL of benchmark arms. Both
  arms are really measured - the delegated arm's worker tokens from its job log plus
  orchestration from `orch-tokens.py`, the direct arm's Claude tokens from the same
  transcript measurement - so the delta is an observed difference, never a modelled
  counterfactual. Prices are parsed from `prices.md`; an unpriced model is reported
  loudly instead of guessed; an unverified arm never counts as a win.
- `docs/benchmark.md`: the method, the JSONL schema, and what the numbers are not.
  The delta is scoped to the measured task set with its n, explicitly not a bound or
  a general multiple - the receipts' "floor" argument does not transfer to a
  comparison where both arms actually ran.
- README's savings FAQ now points at this project's own methodology; the upstream
  three-task benchmark stays cited but labelled as a previous model generation.
- Cross-review caught three defects in the first cut: per-arm totals summed a
  different row set than the delta (a mixed ledger reported delegated $3.53 against
  direct $2.40 while claiming delegation was $1.23 lower), direct arms accepted
  nonzero `worker_tokens` in a direction that flattered delegation, and
  caller-relative ledger paths resolved against the repo root. Rounding is now applied
  once per row, so no two lines of a report can disagree about the same figure.

## 0.7.10 - 2026-07-27

- Logo: a `/e` terminal monogram (the slash is how the plugin is actually invoked),
  shipped as outlined SVG in a dark and a light variant plus PNG renders; replaces
  the emoji in the README hero.

## 0.7.9 - 2026-07-27

- Added Claude Opus 5 as the premium keyless Claude subscription worker
  (`--with opus`) alongside the cheap Sonnet fallback, with route pricing checks and
  receipt honesty for the Fable-priced orchestration reference.

## 0.7.8 - 2026-07-24

- This changelog.

## 0.7.7 - 2026-07-24 - simmer hardened by its first dogfood

Findings came from a real simmer run executed while a second Claude session was
actively editing the same worktree - the exact environment the old text silently
assumed away.

- Shared-worktree safety: dirty tree recommends `git worktree` isolation for the
  loop; declining records `shared_tree: yes` and makes staging/judging discipline
  mandatory.
- Checkpoints stage only lap-authorized paths that were clean at lap start; a path
  carrying another session's hunks stops the checkpoint - never a blended commit.
- The lap judge classifies concurrent edits (fire's rule); foreign paths never
  enter verdicts or receipts. Receipt diffs count checkpoint commits only.
- Branch-scoped loop state with a collision-safe slug (slash replacement + 6-char
  hash); resume validates the recorded base is an ancestor of HEAD, so a
  recreated branch cannot inherit a stale loop.
- Worker routing for loops: `worker:` per contract (codex default,
  `--with sonnet`); a quiet errors-only Sonnet log is never read as a dead
  worker - no-result + quiet log = indeterminate, surfaced, never auto-relaunched.
- Codex lap ledger lines carry `branch` for cross-loop attribution.

## 0.7.6 - 2026-07-24 - the measurement layer becomes executable

- `scripts/orch-tokens.py`: single implementation of transcript-based
  orchestration measurement (session-id located exactly, one-match-only,
  datetime window, invalid in-window usage aborts the whole window - no partial
  totals; no output means drop the line).
- `scripts/tab.sh`: the running tab from `~/.expo/ledger.jsonl`.
- First behavior tests in CI: hermetic fixture transcripts assert exact sums,
  boundary inclusivity, fractional-second regression, usage-null and
  ambiguous-match aborts; rc checked on every invocation so a crash cannot pass
  as an empty window.

## 0.7.5 - 2026-07-24 - honest per-run savings + a release gate

- Receipts carry an equal-volume delta (floor): this run's combined token volume
  priced at Fable list minus the measured all-in - fully measured, never
  presented as a bound on actual savings (the counterfactual is not run). A CI
  invariant rejects any unqualified savings wording, all word forms,
  case-insensitive.
- `scripts/release.sh`: refuses no-op releases (same-version installer updates
  are silently ignored - hit twice before this existed), fetches and requires
  not-behind, full check before bump, byte-identical bump restore on pre-commit
  failure, resume paths for failed push and failed refresh, user-scope-aware
  verification that the installed copy matches HEAD.

## 0.7.4 - 2026-07-24 - README redesign; GPT-5.5 retired

- README rebuilt: centered hero with the flow diagram and badges, quickstart
  first, command and tier tables, collapsible FAQ.
- GPT-5.5 removed from every operative surface (prices, recommendations,
  receipts machinery); the kitchen runs GPT-5.6 tiers and Sonnet 5 only.

## 0.7.1-0.7.3 - 2026-07-23/24 - cross-review fixes on the 0.7.0 features

- taste pins `-c model=gpt-5.6-sol` - "reviews stay on sol" became a mechanism,
  not a hope about the user's config.
- Orchestration windows split per job (`$JOB/started`) vs per run (`started:`),
  eliminating a 2-3x double-count in the running tab; measurement snippet
  hardened (datetime parsing, empty-window contract).
- simmer picks its GPT-5.6 tier once per loop; mixed-tier receipts price each
  job at its own model's blend.
- Pricing freshness watchdog: a stale as-of date warns then fails CI; an expired
  "through YYYY-MM-DD" price note fails.
- Flow diagram artwork; docs sync across templates and README.

## 0.7.0 - 2026-07-23 - tier routing + measured orchestration

- Model-tier routing: fire picks gpt-5.6-sol/terra/luna by task shape
  (`--tier` overrides); serve threads the tier to refire; the tier rides the
  invocation as `-c` flags.
- Orchestration cost measured from the session transcript instead of the
  historical "~5-7k per run" estimate.

## 0.6.0 - 2026-07-23 - the fork

- Renamed sous-chef -> expo; GLM routes removed (Codex + Sonnet only); folded in
  the fixes that were pending upstream (self-check blind spots, stale claims,
  GPT-5.6 pricing); refire gained worker routing. Full attribution retained.
