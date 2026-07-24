<div align="center">

# 🧑‍🍳 expo

**Fable 5 orchestrates and reviews; GPT-5.6 or Sonnet 5 implements.**

*Your head chef doesn't chop onions.*

<br>

![MIT](https://img.shields.io/badge/license-MIT-blue)
![Claude Code plugin](https://img.shields.io/badge/Claude_Code-plugin-d97757)
![Codex CLI ≥ 0.134](https://img.shields.io/badge/Codex_CLI-%E2%89%A50.134-black)
![Workers](https://img.shields.io/badge/workers-GPT--5.6_·_Sonnet_5-4a9eff)

<br>

![expo flow: you hand the order to Claude, the head chef (Fable 5), who plans, writes the ticket, reviews every line, and re-runs the checks; the worker (GPT-5.6 sol/terra/luna, or Sonnet 5) implements in a sandbox with no say over what ships; a cross-review pinned to sol checks the diff; the run ends verified and served, with a measured cost receipt.](docs/expo-flow.png)

<sub>expo is a fork of [sous-chef](https://github.com/tomascupr/sous-chef) by Tomas Cupr (MIT) - the expediter who calls the orders and checks every plate at the pass. Same two-model kitchen; this line is actively developed here.</sub>

</div>

---

A Claude Code plugin that splits coding between two frontier models the way a
kitchen splits work. **Fable plans, writes the ticket, reviews every diff line by
line, and re-runs the checks itself. Codex (or Sonnet) does the implementation,
with no say over what ships.**

The split is economic: the most expensive model on the line spends its tokens on
judgment, the worker's tokens go to bulk. Everything runs on subscriptions you
already have - no API keys.

> Codex saying "tests pass" is a sentence; `pnpm test` output is a fact.
> Claude re-runs everything itself.

## ⚡ Quickstart

Requirements: [Codex CLI](https://developers.openai.com/codex/cli) ≥ 0.134,
authenticated (`codex login` - a ChatGPT subscription is enough).

```text
/plugin marketplace add mightymattys/expo
/plugin install expo@expo
```

Then, inside a repo:

```text
/expo:mise
```

`/mise` is idempotent - re-run it anytime as a health check, and after a plugin
update to refresh the installed profile.

## 🔥 Two commands

| | |
|---|---|
| **`/expo:serve`** | Task-shaped work, done end to end: implement, cross-review, fix the findings, verify. One announcement up front, one report at the end, a hard budget of five runs in between. **The daily driver.** |
| **`/expo:simmer`** | Goal-shaped work, looped until a command passes: "make the suite green", "get the benchmark under 200ms". A fresh worker run each lap, Claude judging every lap with real command output, on a dedicated branch, with lap caps and no-progress detection. |

Rule of thumb: **serve a task, simmer a goal.** If a serve runs out of budget and
what remains is goal-shaped, it offers to continue as a simmer.

À la carte, when you want to drive the stations yourself:

| Command | What it does |
|---|---|
| `/expo:fire` | Write the ticket, delegate one implementation run, review the diff against a pre-fire baseline, verify. |
| `/expo:taste` | Cross-model review, read-only. Claude validates every finding against the code and filters false positives before you see them. |
| `/expo:refire` | Turn the confirmed findings from a taste into one scoped fix run, then re-verify each finding at its cited location. |
| `/expo:mise` | Setup: Codex CLI + auth checks, delegation profile, `AGENTS.md` scaffold, routing policy. Once per machine, once per repo. |
| `/expo:receipts` | Print the check: the repo's last ten run receipts as a table with a savings total. |

## 🎚️ Model tiers - the right knife for the job

Fire picks a GPT-5.6 tier per task, by shape - the same judgment call that decides
*whether* to delegate also decides *what it's worth*:

| Tier | Effort | Task shape |
|---|---|---|
| `gpt-5.6-sol` | high (`max` for the hardest) | architectural or multi-file complex features, parser-class work, security-sensitive changes |
| `gpt-5.6-terra` | high | standard features, bugfixes, test writing - **the default when unsure** |
| `gpt-5.6-luna` | medium | mechanical bulk: renames, boilerplate, docs, formatting sweeps |

Override with `--tier sol\|terra\|luna`. The tier rides the invocation as `-c`
flags, so it varies per fire; your `~/.codex/config.toml` model applies only when
those flags are deliberately omitted. **Reviews (`taste`) always pin `sol`** -
reviewer strength beats reviewer cost. 5.6's ultra mode stays off for delegated
background runs: it multiplies token spend by design, with nobody watching.

One alternate worker needs no extra key: `fire --with sonnet` sends the ticket to
Claude Sonnet 5 headless on your own Anthropic subscription - the built-in
fallback when Codex hits its usage limit mid-serve.

## 🧾 Receipts - every number measured, nothing guessed

- **Ledger** (`~/.expo/ledger.jsonl`): every Codex-route run appends one line -
  worker tokens from the job log, plus a measured `claude_tokens` figure for the
  head chef's own spend on that round trip, read from the session transcript.
- **Run receipts** (`.expo/receipts/`): every serve and simmer drops a per-run
  receipt - measured tokens on both sides, an API-list dollar split, the diff,
  the verdict, a paste-ready summary. `/expo:receipts` prints the last ten.
- **Freshness is enforced**: CI fails when the price table's as-of date rots or a
  dated price note expires. A model missing from the table warns loudly instead
  of pricing by guess.

## 🛡️ How the kitchen stays honest

**Soft routing, not hard blocks.** A routing policy in `CLAUDE.md` plus skills
that make delegation the path of least resistance. Claude still edits directly
for small surgical fixes - hard-blocking Edit/Write provably makes agents route
around the block. Choose manual or autonomous routing in `/mise`.

**The boundary that IS hard:** delegated Codex runs execute in a
`workspace-write` sandbox with approvals off, and reviews run `read-only`. (The
optional Sonnet worker route has no OS sandbox underneath - trusted repos or a
branch/worktree only.)

**One source of truth for standards.** Repo conventions live in `AGENTS.md`,
which the worker re-reads on every run. Claude reads the same file via an
`@AGENTS.md` import in `CLAUDE.md`.

**Background always, polling never.** Delegated runs execute via
`run_in_background` so the Bash timeout ceiling can't kill them mid-job, and
completion re-invokes Claude.

**Claims are not evidence.** After every delegated run, Claude reviews the diff
line by line and re-runs the verification commands itself.

Every load-bearing decision traces to a documented incident, an official doc, or
a measured comparison - not vibes. A sample:

- **Why background-always:** a single polling loop against a running Codex job
  burned 27% of a weekly Claude quota in ~12 hours producing nothing
  ([anthropics/claude-code#54143](https://github.com/anthropics/claude-code/issues/54143)).
- **Why soft routing:** an agent, blocked three times by a hook, routed around it
  with a Python file-write via Bash
  ([anthropics/claude-code#29709](https://github.com/anthropics/claude-code/issues/29709)).
- **Why findings get validated:** in a 20-review field test, ~3 of 20 reviews
  failed silently.

Full sources for these and every other decision: [docs/design.md](docs/design.md).

## ❓ FAQ

<details>
<summary><b>What does this cost me?</b></summary>
<br>

Two subscriptions: any Claude plan for Claude Code, and a ChatGPT plan for Codex -
`codex login`, no API key needed. Subscription auth is the first-class path for
headless runs: `codex exec` reuses the saved login, tokens auto-refresh even
mid-run, and fire unsets the two env vars (`CODEX_API_KEY`, `CODEX_ACCESS_TOKEN`)
that could silently switch a run to per-token billing. Delegation overhead on the
Claude side is measured per run, not estimated - see the receipts - and is small
enough that only one-file surgical fixes stay cheaper done directly.

</details>

<details>
<summary><b>What does delegation actually save?</b></summary>
<br>

Your own runs measure both sides live: worker tokens from the job log,
orchestration tokens from the session transcript, dollar split at API-list blends
on every receipt. The upstream project also published a seeded three-task
benchmark of the pattern (roughly 10-20x cheaper per task in effective API-price
terms, on the previous model generation) - method and caveats:
[sous-chef#2](https://github.com/tomascupr/sous-chef/issues/2).

</details>

<details>
<summary><b>What do I see while it cooks?</b></summary>
<br>

An announcement first: what was delegated, to which model and tier, the expected
duration (typically 5-20+ minutes per run at high reasoning effort), and the log
path. You keep working; Claude is re-invoked when the job exits. In a serve,
Claude also posts a one-line progress tick every few minutes, distilled from the
job log. Cancel anytime - Claude kills the job and shows you any partial changes
to keep or revert.

</details>

<details>
<summary><b>Does Claude stop writing code?</b></summary>
<br>

No. Small fixes, prototypes, and anything design-ambiguous stay with Claude - the
routing rules themselves say so. Delegation is announced, never silent - in both
routing modes.

</details>

<details>
<summary><b>How is this different from OpenAI's official codex plugin?</b></summary>
<br>

Three deliberate divergences, each with receipts in
[docs/design.md](docs/design.md): (1) no stop-time review gate - OpenAI's own
README warns it "can create a long-running Claude/Codex loop and may drain usage
limits quickly"; here, review runs inside a pass you explicitly ordered, under a
hard run budget. (2) findings get validated against the actual code before you
see them - raw cross-model reviews over-flag. (3) `/simmer` fills a gap neither
the official plugin nor ralph-loop covers: a delegated implementer inside the
loop with an independent judge outside it.

</details>

<details>
<summary><b>Why not MCP?</b></summary>
<br>

Plain `codex exec` over Bash gives you the sandbox flag, the exit code, stdin for
prompts, and background execution with no extra moving parts. That is why expo
uses a thin wrapper instead of a persistent MCP server.

</details>

<details>
<summary><b>Windows?</b></summary>
<br>

The snippets are POSIX; under Claude Code's Git Bash they should work, but this
is dogfooded on macOS.

</details>

## 📦 What's in the box

```text
skills/serve/         the autonomous pipeline: fire, taste, refire, verify, report
skills/simmer/        the loop: the worker cooks, Claude judges, until the goal passes
skills/fire/          delegation skill + ticket template + Sonnet worker route
skills/taste/         cross-review skill + review prompt template
skills/refire/        fix skill: confirmed findings become a scoped fix run
skills/mise/          setup skill
skills/receipts/      the check: per-run cost receipts + savings table
codex/                Codex delegation profile → ~/.codex/expo.config.toml
templates/            AGENTS.md scaffold, CLAUDE.md routing blocks
docs/design.md        the receipts: sources for every design decision
scripts/check.sh      the executable invariant list - CI runs it on every push
```

## 🗑️ Uninstall

`/plugin uninstall expo` removes the skills (and `/plugin marketplace remove expo`
the registration). Using the plugin may also have created (remove by hand if
you're done with them):

- `~/.codex/expo.config.toml` (the delegation profile)
- `~/.expo/ledger.jsonl` (the running tab)
- a "Division of labor (expo, ...)" routing block appended to `~/.claude/CLAUDE.md`
- an `AGENTS.md` scaffold and/or `@AGENTS.md` import line in repos you set up
  (these are yours now - they're useful regardless of the plugin)
- a `.expo/` directory (run receipts, loop state) in repos where a serve or
  simmer ran - git-ignored via `.git/info/exclude`; `rm -rf .expo` per repo when
  you're done with the receipts

## 🤝 Contributing

Field reports welcome - especially Windows, and especially receipts that
contradict [docs/design.md](docs/design.md); it's meant to be corrected.
`scripts/check.sh` is the executable invariant list - run it before a PR.

## 📄 License

MIT © Tomas Cupr (original work, sous-chef) & Matěj Štipčák (this fork, expo)
