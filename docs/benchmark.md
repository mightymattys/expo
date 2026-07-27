# Benchmarking expo delegation

`scripts/bench.sh` is a reporter, not an orchestrator. A human or Claude session
runs each benchmark arm, verifies its task-specific check command, and appends one
JSON object per arm to a JSONL file. The script reads that file and prints a markdown
comparison; it has no quota, state machine, or ability to run an arm.

```sh
scripts/bench.sh path/to/bench.jsonl
```

## Method

Compare the same narrowly scoped task twice. The delegated arm records the worker
tokens from its job log and its orchestration tokens with
`scripts/orch-tokens.py`. The direct arm is Claude implementing that same task; its
`worker_tokens` is zero and its Claude transcript is measured with the same script.
Both arms must run the same check command. Set `verified` to `true` only when that
check passes.

One JSONL line is one measured arm of one task:

```json
{"task":"add-normalize-tests","arm":"delegated","model":"gpt-5.6-terra","worker_tokens":101288,"claude_tokens":15309,"verified":true,"wallclock_s":540}
{"task":"add-normalize-tests","arm":"direct","model":"claude-fable-5","worker_tokens":0,"claude_tokens":88000,"verified":true,"wallclock_s":420}
```

The fields are:

| field | rule |
| --- | --- |
| `task` | A non-empty task identifier; use the same identifier for its two arms. |
| `arm` | Exactly `delegated` or `direct`. |
| `model` | The delegated worker model, or the direct-arm orchestrator model. It must have a row in `skills/receipts/references/prices.md`. |
| `worker_tokens` | A non-negative integer; `0` for a direct arm. |
| `claude_tokens` | A non-negative integer from the arm's transcript measurement. |
| `verified` | `true` only after the task's check command passes. |
| `wallclock_s` | A non-negative elapsed-seconds integer. |

The reporter prices worker tokens at that row's 50/50 API-list blend. It always
prices `claude_tokens` at the `claude-fable-5` blend, on both arms. A model absent
from the price table is shown loudly as unpriced and contributes no dollar figure or
cost total. An unverified arm is marked failed and is excluded from all cost totals
and deltas.

The JSON above is illustrative sample data, not a measurement or benchmark result.
Append real, independently run arms to your own ledger, for example:

```sh
printf '%s\n' '{"task":"my-task","arm":"delegated","model":"gpt-5.6-terra","worker_tokens":123,"claude_tokens":45,"verified":true,"wallclock_s":60}' >> bench.jsonl
```

## Reading the report honestly

The delta is an observed difference on this measured task set only; the report names
the number of compared tasks. It is not a bound, guarantee, or general cross-model
multiple. It does not measure output quality beyond the task's own check command,
review effort, or run-to-run variance unless an arm was repeated.

Dollar figures are API-list terms, never "you paid": subscription runs have $0
marginal cost. The `~` marks estimates derived from the published 50/50 blends, not
an invoice.
