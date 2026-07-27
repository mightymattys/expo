# expo

A Claude Code plugin: Claude (Fable 5) orchestrates and reviews; GPT-5.6 (Codex CLI)
or a Claude worker (Sonnet 5 / Opus 5) implements. This repo is the plugin itself - there is no build
step and nothing to compile; the plugin is markdown, JSON, and TOML. The one exception
is `bench/project`, a Python fixture the benchmark edits.

## Map

- `.claude-plugin/` - plugin + marketplace manifests
- `skills/serve|fire|taste|refire|simmer|mise|receipts/` - the seven skills (each `SKILL.md` + optional `references/`)
- `codex/` - Codex-side delegation profile shipped to `~/.codex/`
- `templates/` - files `/mise` scaffolds into user repos and `~/.claude/CLAUDE.md`
- `docs/design.md` - research receipts behind every design decision
- `bench/` - the cost evidence: a dependency-free Python fixture both benchmark arms
  edit, the task specs, the measured arms, and the rendered table. The only code in the
  repo that is not the plugin; it is never shipped to users.

## Working agreements

- Keep SKILL.md bodies short and goal-directed; this plugin targets frontier models -
  no step-by-step scaffolding a strong model doesn't need.
- Every behavioral claim in docs/design.md must carry a source URL. No uncited claims.
- Command examples must use current syntax: file-per-profile Codex config (>= 0.134),
  no `--full-auto`, no `[profiles.*]` tables.
- Match the kitchen register lightly - names and taglines, not forced metaphors in
  instruction text.
- `scripts/check.sh` is the executable invariant list - run it before a PR; CI runs
  the same script on every PR and push to main.
