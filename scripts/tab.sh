#!/usr/bin/env bash
set -u

ledger=${1:-"$HOME/.expo/ledger.jsonl"}
if [ ! -f "$ledger" ]; then
  printf '%s\n' '{"jobs": 0}'
  exit 0
fi

jq -s '{jobs: length, worker_tokens: ((map(.tokens) | add) // 0), orchestration_tokens: ((map(.claude_tokens // 0) | add) // 0)} as $t | $t + (if $t.orchestration_tokens > 0 then {work_split: (($t.worker_tokens / $t.orchestration_tokens) | .*10 | round / 10 | tostring + "x worker:orchestrator")} else {} end)' "$ledger"
