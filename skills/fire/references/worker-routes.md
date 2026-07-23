# Alternate worker route - Claude Sonnet 5

The default worker is Codex (`codex exec --profile expo`). There is one alternate:
fire the ticket to Claude Sonnet 5 on the user's own Anthropic subscription - no
extra key, no provider config. The ticket, the announce-to-user step, and the
per-job directory (`$JOB`) are identical to a normal fire; only the worker
invocation changes.

The Bash tool's `run_in_background: true` is still the only backgrounding: do not add
`&`, `nohup`, or `disown` inside the command, or the harness can report false
completion while the worker keeps running.

## Claude subscription worker (Sonnet 5, no extra key)

This is the fallback worker when Codex hits its usage limit mid-serve ("try again at
HH:MM"); mise and taste still need Codex, so it is not a Codex-free configuration on
its own. Installed marker: none needed - `claude` is already on the machine running
this plugin.

Preflight for this route: `command -v claude` - no Codex profile check; fire's step-2
hard stop applies to the default Codex route only.

```
Bash (run_in_background: true), cwd = repo root:
claude -p --model claude-sonnet-5 --dangerously-skip-permissions --strict-mcp-config \
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
- Quota is shared with the orchestrator (one Anthropic subscription), but Sonnet 5
  drains it far slower than Opus/Fable-tier orchestration does.
- Cross-model review: when Codex quota recovers, keep Codex as the taster - Sonnet
  implements, the Codex model reviews, the head chef orchestrates. If both worker and
  reviewer are Anthropic models, say so in the report (the cross-lineage value of the
  taste is reduced).
- Honest caveat: `--dangerously-skip-permissions` has no OS sandbox underneath. Only
  fire this route inside a repo you'd trust Codex's `danger-full-access` in, or on a
  branch/worktree.
- No ledger line - `claude -p` emits no token summary.
- Invocation spelling: `/expo:fire --with sonnet <task>` (or the loose phrase "fire
  with sonnet").
