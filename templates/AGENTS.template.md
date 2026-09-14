# [Project name]

[One sentence: what this repo is.]

## Commands

- Dev: `[command]`
- Build: `[command]`
- Test: `[command]`
- Typecheck: `[command]`
- Lint: `[command]`

## Map

- Entry points: `[files]`
- [Key directory] - [what lives there]
- [Key directory] - [what lives there]

## Working agreements

- Simplicity first: minimum code that solves the problem; nothing speculative; no
  abstractions for single-use code.
- Surgical changes: every changed line traces to the task; match existing style; don't
  "improve" adjacent code; never delete code you don't understand - flag it instead.
- Run the test/typecheck/lint commands above before claiming a task is done, and report
  their actual output.
- Never weaken, skip, or disable a check to make a task pass. When a requirement
  conflicts with a check, or with another requirement, stop and report the conflict -
  the conflict is the finding.
- Report verification as it actually ran. A test or lint command run with parts skipped
  or the environment altered is a partial run: say so and say why. Never present it as
  the full one.

## Hard constraints

- Do NOT touch: `[paths - generated code, vendored deps, migrations, CI config]`
- [Non-obvious convention or gotcha an agent would get wrong, e.g. "use pnpm, never npm"]
- [Another, if real. Delete this section's placeholders - keep it under ~10 bullets total.]
