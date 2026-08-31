# Benchmarking expo delegation

`scripts/bench.sh` is a reporter, not an orchestrator. A human or Claude session
runs each benchmark arm, verifies its task-specific check command, and appends one
JSON object per arm to a JSONL file. The script reads that file and prints a markdown
comparison; it has no quota, state machine, or ability to run an arm.

```sh
scripts/bench.sh path/to/bench.jsonl
```

## Method

Both arms run **cold and headless** on the identical starting commit, from the same
task spec, and are judged by the same check command.

- **Delegated arm:** `codex exec --profile expo` at the tier fire's table picks for
  that task shape. Worker tokens come from the job log's closing summary; the
  orchestration tokens are the head chef's own spend on assembling the ticket and
  plating the result, measured with `scripts/orch-tokens.py` over a window that
  contains nothing else.
- **Direct arm:** `claude -p --model <model> --output-format json`, a fresh process
  with no prior knowledge of the repository. Its tokens come from the returned
  `usage` object.

Cold start on both sides is the whole point. An earlier attempt measured the direct
arm as work done inside the session that had just authored the codebase and the spec;
it needed to read nothing and came out roughly ten times cheaper, which measured warm
context rather than delegation. Those numbers were discarded.

Token volume is `uncached input + output` on both sides - what a Codex job log
reports, and `input_tokens + cache_creation_input_tokens + output_tokens` for
`claude -p`. Cache reads are excluded on both arms, so the figures understate real
billed cost for both.

The task spec is written before either arm runs and handed to both verbatim, so the
cost of specifying the work counts against neither. Assembling the ticket around that
spec, plating, and re-running the checks all count against the delegated arm, because
they are real overhead delegation adds. The direct arm's prompt carries one extra
line, `Implement directly; do not delegate.`, without which a Claude process inheriting
the user's global routing policy may delegate the task and stop measuring what this
benchmark is for.

Set `verified` to `true` only when the task's check command passes, checked
independently rather than taken from the arm's own report.

Tier choice is part of the measurement, not a knob to flatter it. Tasks 01, 02 and 04
all ran on terra so that task size is the only variable between them; task 03 ran on
luna because fire's table routes mechanical bulk there, and that is why its ratio is
the highest in the set. Task 04 is a multi-file feature that fire's table would
arguably send to sol at twice the per-token price - it was held at terra deliberately,
and this benchmark does not model what sol would have cost, because that run never
happened.

One JSONL line is one measured arm of one task:

```json
{"task":"add-normalize-tests","arm":"delegated","model":"gpt-5.6-terra","orchestrator":"claude-opus-5","worker_tokens":101288,"claude_tokens":15309,"verified":true,"wallclock_s":540}
{"task":"add-normalize-tests","arm":"direct","model":"claude-opus-5","orchestrator":"claude-opus-5","worker_tokens":0,"claude_tokens":88000,"verified":true,"wallclock_s":420}
```

The fields are:

| field | rule |
| --- | --- |
| `task` | A non-empty task identifier; use the same identifier for its two arms. |
| `arm` | Exactly `delegated` or `direct`. |
| `model` | The delegated worker model. A direct arm has no worker, so it repeats its own orchestrator here, and the reporter refuses a direct row where the two disagree. Must have a row in `skills/receipts/references/prices.md`. |
| `orchestrator` | The Claude model that actually spent `claude_tokens` on this arm. Must have a row in the price table. |
| `worker_tokens` | A non-negative integer; `0` for a direct arm. |
| `claude_tokens` | A non-negative integer from the arm's transcript measurement. |
| `verified` | `true` only after the task's check command passes. |
| `wallclock_s` | A non-negative elapsed-seconds integer. |

The reporter prices worker tokens at that row's 50/50 API-list blend, and each arm's
`claude_tokens` at the blend of the `orchestrator` that actually ran it. Pricing every
arm at one reference orchestrator would overstate a direct arm running a cheaper
Claude - and the direct arm is exactly what delegation is measured against, so that
error would flatter delegation. A model absent
from the price table is shown loudly as unpriced and contributes no dollar figure or
cost total. An unverified arm is marked failed and is excluded from all cost totals
and deltas.

The JSON above is illustrative sample data, not a measurement or benchmark result.
Append real, independently run arms to your own ledger, for example:

```sh
printf '%s\n' '{"task":"my-task","arm":"delegated","model":"gpt-5.6-terra","orchestrator":"claude-opus-5","worker_tokens":123,"claude_tokens":45,"verified":true,"wallclock_s":60}' >> bench.jsonl
```

## Reading the report honestly

The delta is an observed difference on this measured task set only; the report names
the number of compared tasks. It is not a bound, guarantee, or general cross-model
multiple. It does not measure output quality beyond the task's own check command,
review effort, or run-to-run variance unless an arm was repeated. It does not normalise
tokenizers: worker tokens are counted by the worker's tokenizer and orchestration
tokens by Claude's, and Claude 4.7 and later use a newer tokenizer that produces
roughly 30% more tokens for the same text
(https://platform.claude.com/docs/en/about-claude/pricing). The equal-volume delta
therefore prices the run's tokens as if a Claude-only run would have needed the same
count, when the same text would likely take more of them - which makes the floor more
conservative, never less.

Dollar figures are API-list terms, never "you paid": subscription runs have $0
marginal cost. The `~` marks estimates derived from the published 50/50 blends, not
an invoice.
