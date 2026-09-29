---
name: refire
description: Turns confirmed findings from a taste into one scoped fix run, then re-verifies each finding at its cited location. Use after /expo:taste when the user says to fix the findings, apply the review, or refire it. Not for new feature work - that is a fresh /expo:fire.
---

# Refire - the plate failed the pass, send it back

A refire is a fix run whose spec already exists on disk: the `findings.md` a taste
wrote after validating every finding. That is what makes the ticket unusually
precise - file, line, failure scenario, prescribed fix, all confirmed against the
code. Your job is to carry that precision through and then prove each finding is
actually gone.

## Inputs

- Default: the `findings.md` the most recent `/expo:taste` wrote - its report
  names the path; inside `/expo:serve` it is the `findings:` line in the run's
  `state.md`. (Lost the path? It's the newest `findings.md` under `$SCRATCHPAD`.)
- Alternative: a review the user pastes or points to. Validate unfamiliar findings
  against the code first (taste's step 3); never refire a finding you have not
  confirmed yourself.
- No findings available? Say so and stop. Refire without a review is just a fire.

## Choosing the tier

Refire runs on Codex. Two ways its tier is set:

- **Inside a serve:** read state.md's `tier:` line; refire uses the tier fire
  recorded there. Taste stays on Codex/sol.
- **Standalone `/expo:refire --tier <tier>`:** strip the flag from the task text
  and pin `sol`, `luna`, or `astra` as requested. Absent an override, pin `sol`
  rather than falling through to the user's config default, which the vendor now
  points at `gpt-6-astra`.

The findings handoff, the tree anchor, and plating read the working tree via git.

## Preflight

Same as fire, and for the same reasons:

1. Git repo with at least one commit (`git rev-parse HEAD`).
2. Codex profile: `test -f ~/.codex/expo.config.toml` (missing means stop and
   offer `/expo:mise` - Codex silently ignores a missing profile).
3. Mint a fresh job dir: `JOB=$(mktemp -d "$SCRATCHPAD/refire-<label>-XXXXXX")`; a
   short descriptive label is welcome. Then stamp its start: `date -u +%Y-%m-%dT%H:%M:%SZ > "$JOB/started"`
   (`$SCRATCHPAD` is your session scratchpad directory; substitute its absolute path).
4. Snapshot the tree: save `git diff` and `git status --short` into `$JOB` as the
   baseline. The tree is usually dirty here (it holds the diff that was just tasted);
   that is expected; the baseline is what separates the tasted diff from the refire's
   changes.
5. Anchor check: recompute
   `$(git rev-parse --short HEAD)+$(idx=$(mktemp -u); GIT_INDEX_FILE=$idx git add -A && GIT_INDEX_FILE=$idx git write-tree | cut -c1-12)`
   and compare it to the `tree:` line in the findings' header. On mismatch - or no
   `tree:` line at all - the tree has moved since the taste and the cited line numbers
   may have drifted: say so, then treat the file as an unvalidated review (the Inputs
   rule above) - revalidate each finding at its cited location before writing the
   ticket, dropping any that no longer hold.

## The refire ticket

Write `$JOB/ticket.md` with the fire template's XML blocks, specialized:

- `<task>`: "Fix the review findings below. Each is confirmed against the code."
  Then one block per finding: file:line, the defect in one sentence, the evidence
  (quoted code), and the prescribed fix. Taste's `findings.md` is already in this
  shape - carry its CONFIRMED blocks, including `## Security findings`, over
  near-verbatim; its refuted audit-trail section is not refire input.
- `<done_when>`: every listed finding resolved at its cited location, plus the repo's
  verification commands passing.
- `<files>`: touch only files named in the findings. Everything else is off limits.
- `<constraints>`: fix ONLY the findings; no drive-by improvements, no refactors of
  surrounding code, no reformatting.
- `<verification>`: the repo's check commands.
- `<output_contract>`: CHANGED / VERIFIED / OPEN, with a per-finding line under
  CHANGED stating how each was resolved.

## Firing and plating

Identical to fire, backgrounding rule included: a backgrounded run from the repo root
using fire's `codex exec --profile expo` invocation with the chosen tier pinned.
No `&`, `nohup`, or `disown` inside the command.
Announce it in one line (what, which tier, expected minutes, log path, cancel
offer), no polling.

At plating, in addition to fire's outcome checks (exit code, result file present,
sandbox banner):

1. Open each finding's cited location and confirm the defect is gone. A
   finding-by-finding checklist, not a vibe; security findings use the same cited location and re-verification.
2. Run the verification commands yourself.
3. Diff against the pre-refire baseline and compare the changed file set to the
   ticket's `<files>` Touch list, using fire's concurrent-edit rule. Name outside-list
   files, warn `concurrent edit detected - these changes are NOT part of this run's
   review`, exclude them from the refire-attributed delta, and revert or flag worker
   out-of-scope changes.
4. For risky diffs, offer a confirmation `/expo:taste`; two clean models in a row
   is the strongest ship signal this kitchen produces.
5. Add the measured run to the running tab with `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ledger-append.py" --run "$SCRATCHPAD" --session "${CLAUDE_CODE_SESSION_ID:-}"`.

Report resolved security findings separately from other resolved findings, and retain
the limit: security findings were reviewed, not audited.

## Cap

One refire per taste. If a finding survives its refire, do not loop: fix it yourself
or bring it back to the user with what was tried. (Same diminishing-returns rule as
fire's two-delta cap.)
