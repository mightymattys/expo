---
name: simmer
description: Runs a goal loop - Codex implements fresh laps while Claude verifies each against a machine-checkable goal, until it passes or the budget runs out. Use only when the user explicitly asks for a loop ("simmer this", "loop until tests pass", "iterate until green") - it creates a branch and checkpoint commits, so confirm the contract first.
---

# Simmer - reduce until done

A loop is: check state → decide → act → **verify** → repeat, with a stop condition and
a budget. In this kitchen, the selected worker implements inside the loop and you are
the loop's author and judge. The worker never grades its own homework - you run the
checks. And because each lap is a fresh context while your own conversation can be
compacted or restarted mid-loop, neither of you is the loop's memory: the repo is.

Parse `--with <worker>` exactly as fire does: absent or `codex` selects Codex;
`--with sonnet` selects Claude Sonnet 5. For Codex, if `codex` is missing or
`~/.codex/expo.config.toml` doesn't exist, stop and offer `/expo:mise` first
(Codex silently ignores a missing profile - `test -f`). For Sonnet, require
`command -v claude`. The repo must have at least one commit (the no-progress guard
needs `HEAD`).

## 1. Write the loop contract first - and get it confirmed

A loop is only as good as its stop condition. Establish with the user, and confirm
before lap 1 (simmer creates a branch and makes commits - say so):

- **Goal** - ONE measurable end state, e.g. "`pnpm test` exits 0 with the 12 new
  migration tests passing".
- **Check commands** - the exact commands that verify the goal (tests, typecheck,
  lint, a curl). Machine-checkable or it doesn't belong in a loop: if success can't be
  verified cheaply by a command, don't simmer - do it interactively instead.
- **Budget** - max laps (default 5) and any wall-clock limit. Tell the user the
  realistic wall time: each lap is a full worker run, typically 5–20 minutes at
  high reasoning effort.
- **Shared worktree** - before creating the branch, run `git status --porcelain`.
  If it carries changes outside the user's current request, warn that a second
  session appears active in this worktree and that branch switching moves its
  uncommitted WIP onto the loop branch. For a dirty tree, recommend isolating the
  loop with `git worktree add <path> -b expo/<task>` so its branch, checkpoints,
  checks, and `.expo/` state never touch the shared working tree. If the user
  declines, proceed here but record `shared_tree: yes` in the contract; the staging
  and judging rules below are then mandatory, not advisory.
- **Branch** - create `expo/<task>` yourself before lap 1 and tell the user its
  name up front, either in the linked worktree above or by switching this tree.
  Never loop directly on main: a bad run must be a branch delete, not an incident.
  If the repo or user config has commit hooks/gates (pre-commit reviews, staged-tree
  checks), resolve how per-lap checkpoints interact with them BEFORE lap 1 - ask the
  user rather than fighting the gate lap after lap.
- **Worker** - record a `worker:` line for the whole loop: `codex` by default,
  `sonnet` when `--with sonnet` selected it. Worker choice does not change between
  laps.
- **Tier** - pick the GPT-5.6 tier once for the whole loop, by the goal's shape
  (fire's tier table; `--tier sol|terra|luna` overrides), and name it in the
  contract confirmation. Every Codex lap fires on the same tier - a loop that
  silently changed models mid-run would make its lap history incomparable. Record
  `tier: n/a` for Sonnet.

## 2. Loop state - in the repo, out of git

Add `.expo/` to `$(git rev-parse --git-path info/exclude)` if it isn't there
yet, then write the contract (goal, check commands, budget, branch with its base
commit, `worker:`, `tier:`, `shared_tree: yes` when applicable, and the UTC start
time as a `started:` line - the receipt reads it back for wallclock, same field
name as serve's state.md) to `.expo/loop-<branch-slug>.md` and create
`.expo/progress-<branch-slug>.md`. Derive `<branch-slug>` from the branch name with
`/` replaced by `-` plus a 6-char suffix from a stable hash of the full branch name:
`<slash-replaced>-$(printf %s "$branch" | shasum | cut -c1-6)`. In a linked worktree
these files live in that worktree's `.expo/`. The state survives session restarts
because it lives in the repo worktree; the ignore keeps it out of diffs, checkpoint
commits, and the no-progress guard.

Ownership is strict: `.expo/loop-<branch-slug>.md` is yours - the contract plus one
verdict line per lap under `## Laps`; `.expo/progress-<branch-slug>.md` is the
worker's notebook. The worker never writes the loop file.

On invocation, derive `<branch-slug>` from the current branch and use only
`.expo/loop-<branch-slug>.md` as a resume candidate. Also surface any loop file
whose recorded branch no longer exists as stale; never resume it. If the candidate's
recorded task and branch match, validate that its recorded base commit is an ancestor
of the current branch HEAD with `git merge-base --is-ancestor <base> HEAD`; failure
is stale - surface it. Then start where the loop definition starts - check state: run
the check commands, and if the goal already passes, that's a done report, not a lap.
Otherwise count the budget from the `## Laps` lines - and prove the fate of any
`fired` line with no verdict via its recorded job dir before counting it. A result
file present means the run landed unjudged (judge it now and rewrite the line). For
Codex, a log still growing means the worker is still cooking. Liveness is never
inferred from log growth alone: `no-result + quiet log = INDETERMINATE` -
surface it to the user and never auto-relaunch into the same tree. Lines before the
most recent `pass` belong to a finished episode, so a regression after a pass counts
laps fresh (the cycling guard still reads all of them). This is what lets a `/loop`
trigger on the same machine re-enter a simmer. A task mismatch is stale too; show it
to the user before starting fresh.

## 3. The lap

For each iteration, until the goal passes or the budget is spent:

1. **Fire the worker** - mint a fresh per-lap job dir and stamp its start
   (`date -u +%Y-%m-%dT%H:%M:%SZ > "$JOB/started"`); never reuse ticket, result,
   or log paths between laps. Snapshot the lap-start changed file set, then write
   `$JOB/ticket.md`: the full contents of `.expo/loop-<branch-slug>.md` (contract
   plus lap history), lap number, the verbatim failing output from last lap, the
   paths this lap may change, and the instruction to do ONE coherent unit of work,
   update `.expo/progress-<branch-slug>.md` (never the loop file - that is the
   judge's), and stop.

   Background using fire's rule - no `&`, `nohup`, or `disown` inside the command.
   For `worker: codex`, keep fire's `codex exec` invocation with
   `env -u CODEX_API_KEY -u CODEX_ACCESS_TOKEN`, `--profile expo`, the flags read
   from this loop's `tier:` line
   (`-c model=gpt-5.6-<tier> -c model_reasoning_effort=<effort>`),
   `--output-last-message "$JOB/result.md"`, stdin from `$JOB/ticket.md`, and
   stdout/stderr in `$JOB/job.log`. For `worker: sonnet`, use the `claude -p`
   subscription invocation in
   [../fire/references/worker-routes.md](../fire/references/worker-routes.md), reading
   the same `$JOB/ticket.md` and writing the same `$JOB/result.md` and
   `$JOB/job.log`.

   When you launch, append `lap N: fired <abs job dir>` under `## Laps` - the
   budget counts launches, not landings, so a crash mid-lap can't un-spend a lap,
   and the job dir is how a later resume proves this run's fate. Do not poll while
   it runs; progress ticks, if the user has them on, follow fire's "While it cooks"
   - armed per lap, disarmed at lap exit.
2. **Verify yourself** - when it exits, first check the job outcome (non-zero exit or
   missing result file = failed lap: rewrite its line to `lap N: fail - run error:
   <cause>`, read the log tail, surface the error, and decide with the user whether
   to retry - a retry is a new launch under the next lap number - or stop). Compare
   the lap's changed file set against its lap-start snapshot and authorized paths,
   applying [fire's Plating step 3 concurrent-edit rule](../fire/SKILL.md#plating---when-the-job-exits).
   Name foreign paths with `concurrent edit detected - these changes are NOT part
   of this run's review` and exclude them from this lap's checkpoint and verdict;
   revert worker out-of-scope paths or surface them before acceptance.

   Then run the check commands. Their output is the verdict; the worker's claims are
   not. Record it: rewrite lap N's `fired` line to the verdict - `lap N: pass` or
   `lap N: fail - <first failing command>: <error identity>`. Strip timestamps,
   durations, and temp paths so an identical failure produces an identical line,
   but keep the failing test or error name - `pnpm test: FAIL` is too coarse to
   mean anything. You write these lines, never the worker: they are the loop's
   durable lap counter and its convergence evidence.
3. **Checkpoint** - stage only the paths authorized by this lap's instruction, using
   explicit path arguments, then commit them (`simmer <task> lap N`).
   `.expo/progress-<branch-slug>.md` is git-excluded and is never committed. Never
   use `git add -A` on a shared tree. With `shared_tree: yes`, whole-path staging is
   safe only for authorized paths that were clean at lap start. If an authorized
   path was already dirty at lap start or changed concurrently during the lap, STOP
   the checkpoint and surface it - never stage a file whose content mixes two
   sessions' work. If a checkpoint would stage an unauthorized path, stop the lap
   and surface it. Git history is how a loop survives a bad lap: a regression is a
   revert, not an argument.
4. **Judge, decide, and say so** - give the user a one-line lap report (lap N of M:
   what changed, check result) and add the lap to the running tab per fire's plating -
   Codex laps append the same `~/.expo/ledger.jsonl` line with `"skill":"simmer"`
   plus `"lap":N` and `"branch":"<branch>"`, pass or fail (a failed lap still spent
   quota). Sonnet laps append no ledger line because `claude -p` emits no token
   summary. Then:
   - Checks pass → done. Report laps used, final check output, the commits made, and
     **the branch name** - merging (or deleting) it is the user's call. Mention that
     `.expo/loop-<branch-slug>.md` and `.expo/progress-<branch-slug>.md` are loop
     scaffolding they can drop, while
     `.expo/receipts/` keeps the repo's run receipts; don't delete either
     unasked. Offer to switch them back to their original branch.
   - Checks fail, progress made → next lap, feeding the failure output back.
   - **No progress or cycling** - the tree hash (`git rev-parse HEAD^{tree}` plus a
     hash of the lap-attributed working diff, excluding classified foreign paths)
     didn't change, or this lap's failure signature already appears in any earlier
     `## Laps` line (the loop is circling, not converging) → stop and escalate to
     the user. A loop that isn't converging doesn't need more laps, it needs a
     different approach (often: you take over, or the ticket was under-specified).
   - Budget spent → stop, report honestly where it landed.

   Whatever the terminal outcome, write the run's receipt per
   [../receipts/references/receipt-template.md](../receipts/references/receipt-template.md).

## 4. Rails (non-negotiable)

- Lap cap always set - an unbounded loop is a quota incident, not a workflow.
- Verification commands run by you, in your shell, every lap.
- No-progress and cycling detection every lap, judged from the `## Laps` lines you
  wrote - the lap cap, not the guard, remains the primary safety.
- Loops with write access stay on their branch. Merging is a human decision.
- **On interrupt or abort**: kill the worker task, run `git status`, commit or stash
  only the authorized partial lap with a clear label
  (`simmer <task> lap N (interrupted)`) - never stash foreign changes on a shared
  tree - rewrite the lap's `fired` line to `lap N: interrupted`, and report the
  branch + last checkpoint so the user knows exactly where their work is.

## Relation to native loop primitives

- `/goal` loops Claude-as-worker with a small-model judge; simmer loops a fresh
  delegated worker with Claude as judge - use simmer when implementation bulk
  belongs outside the orchestration session, `/goal` when the work needs Claude
  itself.
- For recurring maintenance loops (babysit CI, rebase branches, flaky-test repair),
  compose with `/loop 30m /expo:simmer …` - same machine, same working tree, so
  a fresh session derives the current branch's
  `.expo/loop-<branch-slug>.md` and resumes at the recorded lap. A cloud `/schedule`
  routine runs on a fresh clone and never sees local loop state - don't compose
  simmer with it.
