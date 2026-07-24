# Design receipts

Every load-bearing decision in expo traces to a documented incident, an official
doc, or a measured comparison - collected via a multi-source research sweep on
2026-07-02, updated 2026-07-04. Corrections welcome via issues.

## Why an orchestrator/implementer split at all

- **Cross-model review beats self-review.** A reviewer from a different training
  lineage doesn't share the author's blind spots - our claim, but the supporting data
  points the same way: in one 36-round blind head-to-head (Blake Crosley's test, as
  relayed by a dev.to roundup), Claude Code's output was rated cleaner 67% of the time
  vs Codex's 25%. Two models that disagree that often make useful reviewers for each
  other - provided findings are validated before applying, which is why `/taste` has a
  mandatory validation step.
  Source: [Claude Code vs Codex - 500 Reddit developers](https://dev.to/_46ea277e677b888e0cd13/claude-code-vs-codex-2026-what-500-reddit-developers-really-think-31pb).
- **Cost asymmetry.** In madewithlove's measured delegation setup, "Codex did about
  20x more work than Claude" with ~5–7k tokens of orchestration overhead per round
  trip (and a trivial one-line change cost 13,584 combined tokens - hence fire's
  size threshold). Daniel Vaughan's guide adds that running both mid-tier
  subscriptions often proves more cost-effective than a single top-tier Claude
  subscription.
  Sources: [madewithlove](https://madewithlove.com/blog/claude-up-front-codex-in-the-back/),
  [Using Claude Code and Codex together](https://codex.danielvaughan.com/2026/03/27/using-claude-code-and-codex-together/).
- **Division of labor consensus** across independent write-ups: Claude excels where
  "the right action is not obvious before you start"; Codex optimizes throughput on
  well-specified tasks and "will not change adjacent code unless asked."
  Source: [danielvaughan multi-tool guide](https://codex.danielvaughan.com/2026/03/27/using-claude-code-and-codex-together/).

## Why soft routing instead of hard-blocking Edit/Write

- Anthropic: "Permission rules are enforced by Claude Code, not by the model.
  Instructions in your prompt or CLAUDE.md shape what Claude tries to do, but they
  don't change what Claude Code allows." ([permissions docs](https://code.claude.com/docs/en/permissions))
  So prose alone is never enforcement. But full tool denial has a documented
  workaround problem:
- [anthropics/claude-code#29709](https://github.com/anthropics/claude-code/issues/29709)
  (closed, not planned): "The hook correctly blocked my Edit attempts three times.
  Instead of accepting the block, I circumvented it by running a Python file-write
  operation via the Bash tool." Edit/Write denies don't cover arbitrary subprocess
  writes, and the delegation CLI itself needs Bash - a hard block that can't actually
  hold is worse than an honest routing policy.
- Every serious published setup - OpenAI's own
  [codex-plugin-cc](https://github.com/openai/codex-plugin-cc),
  [codex-orchestrator](https://github.com/kingbootoshi/codex-orchestrator),
  [myclaude](https://github.com/cexll/myclaude) - enforces roles via subagent tool
  whitelists and by making delegation the path of least resistance, not via global denies.
- The hard boundaries that DO hold are on the Codex side: `sandbox_mode`
  (workspace-write for implementation, read-only for review) and `approval_policy`
  are process-level, not prompt-level.

## Why two routing modes (manual vs autonomous)

- Skills are model-invocable without a typed slash command; the frontmatter
  description is the trigger surface Claude reads to decide when to invoke a skill.
  Source: https://code.claude.com/docs/en/skills
- Because the description is always-on, a prohibition written into it ("on-demand
  only") blocks autonomous triggering in every session, and a CLAUDE.md policy that
  contradicts its own skill's description degrades trigger reliability. Hence the
  descriptions defer to "the routing policy" and the mode lives in exactly one place -
  the block /mise installs in the user's CLAUDE.md. (First-party design reasoning
  building on the skills doc above.)
- The skillUsage gate: the harness lists a never-invoked skill name-only - invisible
  to model triggering - until a skillUsage entry exists in ~/.claude.json. First-party
  verification, 2026-07-03: content-independent, deterministic per user. Autonomous
  setup therefore checks the entries and warns instead of assuming triggering works.
- Autonomous is not unattended: "Permission rules are enforced by Claude Code, not by
  the model" (https://code.claude.com/docs/en/permissions), so permission prompts
  still gate every delegated `codex exec`. That is why autonomous setup offers an
  explicit allow rule instead of pretending prose is enforcement.
- Why manual is the recommended default: autonomous mode makes serve the default
  handler for ordinary implementation requests - a spend decision on another vendor's
  quota (see the ~20x cost asymmetry receipts above:
  https://madewithlove.com/blog/claude-up-front-codex-in-the-back/) that users should
  opt into knowingly. The one-line announcement survives in both modes; what changes
  is who pulls the trigger.

## Why background-always, polling-never

- [anthropics/claude-code#54143](https://github.com/anthropics/claude-code/issues/54143):
  a single review delegation with an unbounded polling loop consumed 27% of a weekly
  Claude quota over ~12 hours while producing nothing. "In agent systems, budget is
  part of the control plane."
- Foreground Bash has a hard 600s ceiling, and long-run delegations take 5–20+ minutes:
  [#25881](https://github.com/anthropics/claude-code/issues/25881) ("When a command
  hits the 600s ceiling, it is killed mid-execution"), timeout env-var reliability:
  [#34138](https://github.com/anthropics/claude-code/issues/34138). Both closed as
  not planned - raising timeouts is not the sanctioned path.
- The sanctioned path is detach-and-notify: `run_in_background` re-invokes the agent
  on exit ([interactive-mode docs](https://code.claude.com/docs/en/interactive-mode)),
  and the Monitor tool (April 2026) replaces polling with until-conditions.
- **Only the harness backgrounds the job.** Dogfooding found a double-detached
  invocation (`&`/`disown` inside a `run_in_background` Bash) where Claude Code
  tracked a wrapper that exited immediately and sent a false completion while Codex
  kept running orphaned; fire now makes tool-level backgrounding the only
  backgrounding.
  Source: [sous-chef#5](https://github.com/tomascupr/sous-chef/issues/5).
- Paced progress ticks compose with detach-and-notify rather than reverting to
  polling: the [#54143](https://github.com/anthropics/claude-code/issues/54143)
  failure mode is an unbounded polling loop, while a ticker is
  bounded by the run, self-disarming on exit, and reads the local job log without
  ever querying the worker. Pacing ticks under the prompt cache's 5-minute TTL keeps
  each wakeup on a warm cache instead of re-reading the full conversation
  ([prompt caching docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)).
  Completion still arrives via re-invocation; ticks only narrate the wait.

## Why AGENTS.md is the standards channel

- Official: "Codex reads AGENTS.md files before doing any work" and "rebuilds the
  instruction chain on every run" - including `codex exec`, so a driving agent gets
  repo standards injected for free.
  ([AGENTS.md guide](https://developers.openai.com/codex/guides/agents-md))
- Layering: global `~/.codex/AGENTS.md` → repo root → nested dirs, concatenated
  root-down, closer files win, 32 KiB combined cap.
- Claude Code reads CLAUDE.md, not AGENTS.md; the supported bridge is an `@AGENTS.md`
  import ([memory docs](https://code.claude.com/docs/en/memory)) or a symlink. One
  file, two readers, zero drift.

## Why a file-per-profile Codex config

- Breaking change in Codex 0.134.0: "`--profile` no longer reads
  `[profiles.profile-name]` from config.toml, and the top-level `profile = "..."`
  selector is no longer supported." Profiles are now standalone
  `~/.codex/<name>.config.toml` files.
  ([config-advanced](https://developers.openai.com/codex/config-advanced))
  Most guides published before mid-2026 show the old syntax, which modern Codex
  silently ignores.
- `codex exec` defaults to a read-only sandbox; `--full-auto` is deprecated in favor
  of explicit `--sandbox workspace-write`
  ([non-interactive docs](https://developers.openai.com/codex/noninteractive)).
- The profile pins only execution-safety settings (approval policy, sandbox mode,
  network access), mirroring OpenAI's own plugin: "Leave --effort unset... Leave model
  unset by default" - model/effort belong in the user's `config.toml`.
  ([codex-plugin-cc](https://github.com/openai/codex-plugin-cc))

## Why `env -u CODEX_API_KEY -u CODEX_ACCESS_TOKEN` (and NOT `-u OPENAI_API_KEY`)

- Subscription auth is fully supported for headless runs: "`codex exec` reuses saved
  CLI authentication by default"
  ([non-interactive docs](https://developers.openai.com/codex/noninteractive)), and
  "For sign in with ChatGPT sessions, Codex refreshes tokens automatically during use
  before they expire" - including a built-in 401 refresh-and-retry mid-run
  ([auth docs](https://developers.openai.com/codex/auth),
  [CI/CD auth](https://developers.openai.com/codex/auth/ci-cd-auth)). Some models on
  ChatGPT plans (GPT-5.5 among them) are listed as not available under API-key auth
  at all ([pricing](https://developers.openai.com/codex/pricing)).
- The env vars that DO override the login in `codex exec` are `CODEX_API_KEY`
  (exec-only, "takes precedence over any other auth method") and
  `CODEX_ACCESS_TOKEN` - so those are what fire unsets to pin the run to the
  subscription.
- The widely-circulated advice to unset `OPENAI_API_KEY` (e.g. in
  [claude-codex-collab](https://github.com/AlessioZazzarini/claude-codex-collab)) is
  based on 2025-era behavior. Fixed November 2025: "The CLI no longer implicitly logs
  in using the env variable. You now must explicitly log in using
  `codex login --api-key`"
  ([openai/codex#2341](https://github.com/openai/codex/issues/2341), closed by an
  OpenAI maintainer). Worse than useless now: unsetting it breaks custom model
  providers that use `env_key = "OPENAI_API_KEY"`.
- Quota exhaustion and hard auth expiry both surface as exec exit 1 with the detail
  only in the stream ("You've hit your usage limit…" / persistent 401) - which is why
  fire's plating step reads the log tail on failure and names the two cases for the
  user.

## Why the ticket contract is XML blocks

- OpenAI's prompting guidance for driving Codex from another agent: "Prefer explicit
  prompt contracts over vague nudges"; "Tell Codex what done looks like. Do not assume
  it will infer the desired end state." Stable XML tags (`<task>`,
  `<structured_output_contract>`, `<verification_loop>`, `<action_safety>`) beat
  raising reasoning effort.
  ([gpt-5-4-prompting skill](https://github.com/openai/codex-plugin-cc/blob/main/plugins/codex/skills/gpt-5-4-prompting/SKILL.md))
- "Codex has no memory of your session. Without a structured spec... Codex will make
  assumptions." ([claude-codex-collab](https://github.com/AlessioZazzarini/claude-codex-collab))
- Delegation has real overhead (~5–7k orchestration tokens per round trip; a trivial
  one-line change cost 13,584 combined tokens) - hence the "cook it yourself" threshold
  in `/fire`. ([madewithlove](https://madewithlove.com/blog/claude-up-front-codex-in-the-back/))

## Why `/taste` validates findings before presenting them

- Field report after ~20 plugin-driven reviews: Codex reviews ran shallower than Opus
  reviews on the same diffs, ~3 of 20 failed silently, and adversarial mode "doesn't
  adjust its expectations based on the scale or criticality of the project" - flagging
  missing circuit breakers on a 500-line cron script.
  ([mejba.me](https://www.mejba.me/blog/codex-plugin-claude-code-adversarial-review))
- The fix (via [nathanonn](https://www.nathanonn.com/)): a validation step where Claude
  "analyzes each comment against the actual codebase" before applying anything -
  adopted wholesale as step 3 of `/taste`.
- Debate cap: two rounds, then take over - convergence between independent reviews is
  the signal; extended argument has diminishing returns.
  ([claude-codex-collab](https://github.com/AlessioZazzarini/claude-codex-collab))
- Refutation verdicts persist: a REFUTED label is an unreviewed judgment call, and
  previously the reasoning was discarded (report said "N refuted", nothing more),
  so a wrongly refuted blocker died silently and its rate couldn't even be measured.
  Now `findings.md` carries a refuted audit-trail section and the report names
  refuted blockers with reasons - raised by the first community question on
  cross-model disagreement, which also surfaced that a default serve is Codex
  reviewing its own diff (hence serve's unconditional same-lineage disclosure).
  ([issue #1](https://github.com/tomascupr/sous-chef/issues/1))
- Fixing is deliberately a separate skill (`/refire`) rather than taste applying its
  own findings: the reviewer stays read-only by CLI flag (role separation that a
  prompt can't guarantee), and the review-to-fix boundary is exactly where a human can
  step in à la carte - or not, inside a `/serve` they ordered.

## Why fast mode is surfaced, not inherited silently

- Codex fast mode ("Fast mode increases supported model speed by 1.5x and consumes
  credits at a higher rate... 2.5x the Standard rate for GPT-5.5 and 2x the Standard
  rate for GPT-5.4",
  [speed docs](https://developers.openai.com/codex/speed)) is enabled by a single
  user-level key (`service_tier = "fast"`; the `fast_mode` feature flag defaults to
  true) and applies only under ChatGPT sign-in.
- The tier flows into headless `codex exec` runs: `service_tier` lives in the core
  config shared by all frontends, and exec loads the user's config.toml by default
  (source-verified in openai/codex `codex-rs/core`; the docs don't state it either
  way). A user who turned fast on for interactive latency would otherwise pay 2.5x on
  every background delegation - a silent drain on the shared 5-hour window.
- But pinning standard in the shipped profile would override a deliberate user choice,
  and a 1.5x speedup does compound across a serial serve pipeline. So `/mise` surfaces
  the tradeoff and offers a commented `service_tier = "default"` line in the profile;
  the user decides once. ("default" is the explicit standard-routing sentinel; it is
  source-verified but undocumented, so treat it as version-pinned knowledge.)

## Why serve and simmer stay two commands

- The command name is the consent. Serve is a bounded promise (at most 5 Codex runs,
  no branch); simmer creates a branch, makes checkpoint commits, and may run for
  hours. One merged command would either silently escalate into that or stop to ask
  mid-flow, which is the interruption serve exists to remove. Our own UX review found
  simmer's original trigger caught casual phrases like "keep going until tests pass"
  and converted them into loops nobody ordered; the fix was explicit intent, and
  merging would reopen it.
- Exit-condition type is the taxonomy. Anthropic's loops guidance categorizes loops
  by trigger and exit condition
  ([Getting started with loops](https://claude.com/blog/getting-started-with-loops));
  serve exits when a pipeline completes, simmer exits when a command passes. Different
  promise, different name.
- The bridge exists anyway: a serve that exhausts its budget on goal-shaped leftovers
  offers to continue as a simmer.

## Why the review gate is NOT included

- OpenAI's own README on its stop-time review gate: it "can create a long-running
  Claude/Codex loop and may drain usage limits quickly."
  [codex-plugin-cc#248](https://github.com/openai/codex-plugin-cc/issues/248) documents
  the rewake loop under transient failures. `/taste` on demand keeps the human deciding
  when a second opinion is worth the tokens. (`/serve` runs taste as a stage of a pass
  the user explicitly ordered, under a hard run budget - what this project rejects is
  review firing on every stop, unbounded, not review inside an ordered pipeline.)

## Why the only alternate worker is Claude Sonnet 5

- Two workers earn their place: Codex (default, sandboxed, subscription-billed) and a
  Claude Sonnet 5 fallback on the user's own Anthropic plan for when Codex hits its
  usage limit mid-serve - no extra key, no provider config, keyless like the rest of
  the two-subscription setup.
- **The Sonnet route is headless `claude -p`** with `--strict-mcp-config` and
  `--dangerously-skip-permissions`: it inherits the user's subscription auth from the
  default config dir with zero setup. The honest caveat is that it has no OS sandbox
  underneath (unlike Codex's `workspace-write`), so it is for trusted repos or a
  branch/worktree only.

## Why fire picks a GPT-5.6 tier by task shape

- GPT-5.6 ships three tiers (sol/terra/luna) at 3.4x price spread. The head chef
  already classifies every task by shape to decide *whether* to delegate; the same
  classification picks the tier, so tier selection is free judgment already being
  spent - a mechanical rename doesn't need sol's ceiling, an architectural change
  shouldn't get luna's. The default is shape-driven with an explicit `--tier` escape;
  the tier rides the invocation as `-c model=... -c model_reasoning_effort=...` (CLI
  beats the profile) rather than living in `~/.codex/config.toml`, so it can vary
  per-fire without the user editing config between tasks.
- taste stays on `sol` regardless of the fire's tier - a reviewer's misses are more
  expensive than a reviewer's tokens. ultra mode is never enabled on a background run:
  it is a token multiplier, and the [#54143](https://github.com/anthropics/claude-code/issues/54143)
  quota-incident shape is exactly a multiplier running with nobody watching.

## Why orchestration cost is measured, not estimated

- The worker's tokens were always measured (job.log); the head chef's own tokens were
  an estimate ("~5-7k per run"). A `claude_tokens` estimate was proposed upstream and
  rejected as guess-as-data ([sous-chef#5](https://github.com/tomascupr/sous-chef/issues/5)) -
  correctly. The measured version anchors on the live session transcript, which Claude
  Code names for `$CLAUDE_CODE_SESSION_ID` and writes one JSON line per message with a
  `usage` block; summing uncached input + output over a bounded window is the real
  orchestration spend, on the same basis worker tokens use.
- Two windows, deliberately: ledger lines measure per job (`$JOB/started` → now, so
  successive stages have non-overlapping windows and the running tab can sum them
  without double-counting), while the run receipt measures once from the run's
  `started:` - a whole-run figure that is NOT the sum of the job windows. Cross-model
  review of the first draft caught exactly this: one shared anchor made every later
  ledger line contain its predecessors, inflating the tab 2-3x per serve.
- Anchoring on the session id (not a cwd slug or newest-mtime file) locates the exact
  transcript even when the skill runs outside the session's launch directory and when
  another session is active. Unset id, no transcript, or an empty window → drop the
  line, never guess.
- This makes the run's cost fully measured on both sides - a real API-list dollar split
  (worker tokens x worker blend vs orchestration tokens x Fable blend) - rather than a
  worker figure next to a cited counterfactual. The vs-Claude-only "10-20x" claim stays
  a citation, because that counterfactual genuinely isn't run per-fire.

## Why the receipt shows an equal-volume delta, not savings

- The Claude-only counterfactual is not run, so a receipt cannot honestly report what it
  saved against that unseen run. It can price this run's measured combined token volume
  at Fable's list blend and subtract the measured all-in cost; that equal-volume delta is
  computable purely from measured numbers.
- Equal volume deliberately biases down: upstream's benchmark found Claude-only runs
  consumed 5-20x more tokens than delegated runs, so the historical finding makes the
  delta a floor indication ([sous-chef#2](https://github.com/tomascupr/sous-chef/issues/2)).
  Calling it a guaranteed saving would present an extrapolation as a bound, which this
  repo forbids.

## Why refire inherits the worker instead of re-choosing it

- `serve` promises `--with <worker>` "applies to the whole line: fire and refire run
  on that worker" - but refire is a separately-invocable skill, so it needs its own
  worker-selection rule or it would silently fall back to the Codex profile mid-line.
  The fix mirrors fire: standalone refire parses `--with`; inside a serve it reads the
  worker off state.md's `worker:` line rather than re-parsing the task, because the
  worker is a run-level fact the orchestrator already fixed, not a per-stage choice.
  taste deliberately stays on Codex regardless (cross-lineage review), so a
  Sonnet-implemented, Codex-reviewed, Sonnet-refired line keeps its one cross-model
  check. Source: [sous-chef#9](https://github.com/tomascupr/sous-chef/issues/9) item 4.

## Why `/simmer` is shaped the way it is (loop engineering)

- The trend: Boris Cherny (creator of Claude Code), June 2026 - "I don't prompt Claude
  anymore. I have loops that are running... My job is to write loops."
  ([TechCrunch](https://techcrunch.com/2026/06/22/the-ai-world-is-getting-loopy/));
  Addy Osmani named the discipline: "Loop engineering is replacing yourself as the
  person who prompts the agent. You design the system that does it instead."
  ([Loop Engineering](https://addyosmani.com/blog/loop-engineering/), 2026-06-07);
  Anthropic's official framing: loops are "agents repeating cycles of work until a
  stop condition is met."
  ([Getting started with loops](https://claude.com/blog/getting-started-with-loops), 2026-06-30)
- **Verification-cost selection**: "every loop Cherny actually names has a success
  condition a machine can check for free. Verification cost, not loop construction,
  decides what you can automate."
  ([Crosley](https://blakecrosley.com/blog/loops-win-where-verification-is-cheap),
  2026-06-09) - hence simmer refuses tasks without a check command.
- **Worker/judge separation**: in Anthropic's `/goal`, "completion is decided by a
  fresh model rather than the one doing the work." Simmer gets the same property
  structurally: Codex implements, Claude runs the checks and judges.
  ([/goal docs](https://code.claude.com/docs/en/goal))
- **Fresh context per lap, state in files/git**: each `codex exec` starts clean;
  progress persists on disk - the Ralph-loop discipline
  ([ghuntley.com/ralph](https://ghuntley.com/ralph/)) that survived into the
  loop-engineering era. Long resumed Codex sessions hit compaction checkpoint-loss
  loops ([openai/codex#25900](https://github.com/openai/codex/issues/25900)); fresh
  exec + disk state is immune.
- **Budgets and blast radius**: iteration caps as the primary safety mechanism
  ([Anthropic's own ralph-loop plugin README](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop)),
  and write-access loops confined to a branch after documented production incidents
  from unbounded write loops (Crosley).
- Division of labor vs native primitives: `/goal` loops Claude-as-worker; the official
  `ralph-loop` plugin re-feeds the same prompt to the same Claude session. Simmer fills
  the documented gap: a delegated implementer inside the loop with an independent judge
  outside it.

## Why orchestration state lives on disk (serve's state.md, taste's findings.md, simmer's loop files)

- The worker had this discipline from day one - fresh context per run, state in files
  and git ([ghuntley.com/ralph](https://ghuntley.com/ralph/)) - but the orchestrator's
  own state (serve's run budget, the taste→refire findings handoff, simmer's lap
  history) originally lived only in Claude's conversation, where compaction or a
  session restart erases it. That this loses counters and handoffs mid-run is our
  claim - no public incident to cite - but it is the same checkpoint-loss failure
  class documented for long Codex sessions
  ([openai/codex#25900](https://github.com/openai/codex/issues/25900)), and the fix
  is the one the worker already got.
- Scope follows lifetime: serve is a single-session bounded promise, so its `state.md`
  lives in the session scratchpad (survives compaction, not session death - accepted);
  simmer may outlive the session (the same-machine `/loop` composition - a cloud
  `/schedule` clone never sees local state, so simmer doesn't claim it), so
  `loop.md`/`progress.md` live in the repo - ignored, not committed, via
  `.git/info/exclude`, giving durable state with zero footprint in diffs, checkpoint
  commits, or the tree-hash no-progress guard (verified live 2026-07-04: invisible to
  `git status --untracked-files=all` while worker changes stay visible; committed
  state would have permanently defeated the guard).
- Lap verdict lines are written by the judge, never the worker - the same
  completion-decided-by-a-different-party property as `/goal`
  ([/goal docs](https://code.claude.com/docs/en/goal)); worker claims are not
  evidence, so worker-written files can't be the loop's memory of record. The
  recorded signatures also upgrade no-progress detection from "same failure twice in
  a row" to "any signature recurring across laps" - cycling detection - while the lap
  cap stays the primary safety (Anthropic's ralph-loop README, above).
- Findings persist at per-job paths (`$JOB/findings.md`), never a fixed "latest"
  path - fire's stale-fixed-path rule (fixed paths serve stale results as fresh
  successes) applies to the orchestrator's own artifacts too.
- **Plating checks path ownership, not just diffs.** A dogfooding fire overlapped with
  a second Claude Code session; disjoint files showed up in the baseline-aware diff,
  but overlapping edits would have become one confusing merged delta. Fire/refire now
  compare post-baseline paths to the ticket's `<files>` list and exclude outside paths
  from worker attribution.
  Source: [sous-chef#5](https://github.com/tomascupr/sous-chef/issues/5).

## The Karpathy grounding

- His only public statement about his own CLAUDE.md (Jan 26, 2026): agent bad habits
  persist "despite a few simple attempts to fix it via instructions in CLAUDE.md" -
  prose is weak; structure is strong. expo therefore puts the load-bearing parts
  in structure: sandbox flags, background execution, ticket contracts, a validation
  step. ([thread](https://threadreaderapp.com/thread/2015883857489522876.html))
- "Don't tell it what to do, give it success criteria and watch it go" → the
  `<done_when>` block is the center of the ticket.
- "If you have any code you actually care about I would watch them like a hawk" → the
  head chef reviews every delegated diff and re-runs verification personally.
- Note: the viral 186k-star "Karpathy CLAUDE.md" is a third-party derivation of that
  post (by Jiayuan Zhang, `multica-ai/andrej-karpathy-skills`), not his file - worth
  knowing before citing it as gospel.

## CLAUDE.md philosophy (why `templates/CLAUDE.global.example.md` is ~50 lines)

- Official guidance: "target under 200 lines per CLAUDE.md file"; keep facts, move
  procedures to skills, move guarantees to hooks; per-line deletion test: "Would
  removing this cause Claude to make mistakes? If not, cut it."
  ([memory](https://code.claude.com/docs/en/memory),
  [best practices](https://code.claude.com/docs/en/best-practices))
- Fable 5-era addendum: instructions written for weaker models are "often too
  prescriptive... and can degrade output quality" - the skills here state goals and
  contracts, not step-by-step scaffolding.
