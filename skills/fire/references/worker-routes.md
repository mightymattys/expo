# Claude subscription route - Sonnet 5 and Opus 5

The default worker is Codex (`codex exec --profile expo`). The Claude subscription
route has two models on the user's own Anthropic subscription - no extra key, no
provider config. The ticket, the announce-to-user step, and the per-job directory
(`$JOB`) are identical to a normal fire; only the selected model in the worker
invocation changes.

The Bash tool's `run_in_background: true` is still the only backgrounding: do not add
`&`, `nohup`, or `disown` inside the command, or the harness can report false
completion while the worker keeps running.

## Two models, one route

`sonnet` is the cheap fallback when Codex hits its usage limit mid-serve ("try again
at HH:MM"); `opus` is the premium keyless worker. Claude Opus 5 is near Fable coding
ability - SWE-bench Pro 79.2 vs Fable's 80.0
([benchmark](https://codersera.com/blog/claude-opus-5-vs-fable-5-2026/)). Opus drains
the shared Anthropic quota faster than Sonnet, so use that premium deliberately. For
current figures, see [prices.md](../../receipts/references/prices.md).
Mise and taste still need Codex, so this is not a Codex-free configuration on its
own. Installed marker: none needed - `claude` is already on the machine running this
plugin.

Preflight for this route: `command -v claude` is NOT sufficient - it passes while the
route cannot run. `claude -p` needs its own non-interactive credential, and without one
it returns `is_error: true` with `result: "Not logged in · Please run /login"` even for a
user who is signed in to the interactive app. Verified on the maintainer's machine, in
their own shell, in 2026-09; the route has never produced a ledger row. So prove it can
run before firing: `claude auth status` returns JSON, costs nothing and needs no prompt -
require `.loggedIn` to be true. (On the machine above it answers
`{"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}` while
`command -v claude` succeeds.) If you probe with `claude -p --output-format json` instead,
check `is_error`, never `subtype` - that probe returned `subtype: "success"` alongside
`is_error: true`, so a caller reading `subtype` sees a failed run as a good one.
If it fails, the remedy has TWO steps and the first one alone looks like success:
`claude setup-token` prints "token created successfully" but does not log the CLI in -
`auth status` still reports `loggedIn: false` until the printed token is exported as
`CLAUDE_CODE_OAUTH_TOKEN` in the environment the run will use. Observed exactly that way.
Tell the user both steps and stop; never fire into a route whose preflight failed.
The second step has its own trap, seen in practice: `setup-token` prints the token wrapped
across two terminal lines next to an `export CLAUDE_CODE_OAUTH_TOKEN=<token>` suggestion,
and pasting that wrapped text sets only the first half - zsh reports
`not valid in this context` for the remainder, or nothing at all, and the CLI then fails
with the unrelated-looking "Not logged in". So have the user confirm the result rather
than the keystrokes: `echo -n "$CLAUDE_CODE_OAUTH_TOKEN" | wc -c` against the expected
length, then `claude auth status`. Never
ask for the token itself, and never accept one pasted into the conversation - it is a
credential, it belongs only in the user's own environment, and one pasted anywhere else
has to be treated as compromised and rotated.
No Codex profile check; fire's step-2
hard stop applies to the default Codex route only.

```
Bash (run_in_background: true), cwd = repo root:
claude -p --model claude-sonnet-5 --dangerously-skip-permissions --strict-mcp-config \
  < "$JOB/ticket.md" > "$JOB/result.md" 2> "$JOB/job.log"
```

```
Bash (run_in_background: true), cwd = repo root:
claude -p --model claude-opus-5 --dangerously-skip-permissions --strict-mcp-config \
  < "$JOB/ticket.md" > "$JOB/result.md" 2> "$JOB/job.log"
```

- `claude -p` prints the final message to stdout, so `$JOB/result.md` plays the
  `--output-last-message` role. `$JOB/job.log` is errors-only (`claude -p` streams no
  progress to stderr) - progress ticks should report elapsed time, not log contents.
- Uses the default `CLAUDE_CONFIG_DIR`, so the worker inherits the user's
  subscription auth (OAuth/keychain) with zero setup - it runs on the real config
  dir. `--strict-mcp-config` keeps global MCP servers out, but global hooks and
  plugins still load, and so does the user's global `CLAUDE.md` - including this
  plugin's routing block - so **open the ticket with "Implement directly; do not
  delegate."** to keep the worker from contemplating recursion. (`--bare` is not an
  option - it never reads OAuth/keychain.)
- Quota is shared with the orchestrator (one Anthropic subscription). Sonnet drains
  it more slowly; Opus drains it faster.
- Cross-model review: when Codex quota recovers, keep Codex as the taster - the Claude
  worker implements, the Codex model reviews, the head chef orchestrates. If both
  worker and reviewer are Anthropic models, say so in the report (the cross-lineage
  value of the taste is reduced).
- Honest caveat: `--dangerously-skip-permissions` has no OS sandbox underneath. Only
  fire this route inside a repo you'd trust Codex's `danger-full-access` in, or on a
  branch/worktree.
- No ledger line yet - `claude -p --output-format json` does return a `usage` block
  (input/output tokens, cache fields, `total_cost_usd`), so this route is probably
  measurable; expo has not verified it on an authenticated run, so it writes no line
  rather than guessing. Verify with `echo hi | claude -p --output-format json` from a
  logged-in terminal before wiring it up.
- Invocation spelling: `/expo:fire --with sonnet <task>` or `/expo:fire --with opus
  <task>` (or the loose phrases "fire with sonnet" and "fire with opus").
