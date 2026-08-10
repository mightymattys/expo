#!/usr/bin/env bash
# The running tab. One unparseable line must not hide every other run: a token count
# pasted with its thousands separator (`"tokens":97,188`) is invalid JSON, and jq -s
# used to abort the whole tab on it. Bad lines are skipped and counted, never silent.
set -u

ledger=${1:-"$HOME/.expo/ledger.jsonl"}
if [ ! -f "$ledger" ]; then
  printf '%s\n' '{"jobs": 0}'
  exit 0
fi

total=$(grep -c '[^[:space:]]' "$ledger" | tr -d ' ')
# The split divides like by like. A run whose orchestration went unmeasured still
# carries worker tokens, and counting those against a zero denominator inflates the
# ratio in the plugin's own favour - measured at 5.1x against a like-for-like 2.8x on
# a real ledger where 42% of lines had no claude_tokens. Unpaired lines are excluded
# from the ratio and counted, never silently folded in as zero.
jq -R 'fromjson? // empty' "$ledger" | jq -s --argjson total "${total:-0}" '
  {jobs: length, worker_tokens: ((map(.tokens) | add) // 0), orchestration_tokens: ((map(.claude_tokens // 0) | add) // 0)} as $t
  | (map(select(.claude_tokens != null))) as $paired
  | {n: ($paired | length),
     worker: (($paired | map(.tokens) | add) // 0),
     orchestration: (($paired | map(.claude_tokens) | add) // 0)} as $p
  | $t
  + (if $p.orchestration > 0 then {work_split: (($p.worker / $p.orchestration) | .*10 | round / 10 | tostring + "x worker:orchestrator")} else {} end)
  + (if $t.jobs > $p.n then {split_excludes_jobs: ($t.jobs - $p.n)} else {} end)
  + (if $total > $t.jobs then {unreadable_lines: ($total - $t.jobs)} else {} end)'
