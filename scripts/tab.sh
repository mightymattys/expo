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
jq -R 'fromjson? // empty' "$ledger" | jq -s --argjson total "${total:-0}" '
  {jobs: length, worker_tokens: ((map(.tokens) | add) // 0), orchestration_tokens: ((map(.claude_tokens // 0) | add) // 0)} as $t
  | $t
  + (if $t.orchestration_tokens > 0 then {work_split: (($t.worker_tokens / $t.orchestration_tokens) | .*10 | round / 10 | tostring + "x worker:orchestrator")} else {} end)
  + (if $total > $t.jobs then {unreadable_lines: ($total - $t.jobs)} else {} end)'
