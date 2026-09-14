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
  def hit_rate:
    if length == 0 then 0
    else ((map(select(.confirmed >= 1)) | length) / length * 100 | round / 100)
    end;
  def bucket($name; $rows):
    {bucket: $name, n: ($rows | length), hit_rate: ($rows | hit_rate)};
  {jobs: length, worker_tokens: ((map(.tokens) | add) // 0), orchestration_tokens: ((map(.claude_tokens // 0) | add) // 0)} as $t
  | (map(select(.claude_tokens != null))) as $paired
  | (map(select(.skill == "taste"))) as $taste_rows
  | ($taste_rows | map(select(
      (.verdict == "ship" or .verdict == "fix-first")
      and (.confirmed | type) == "number" and .confirmed >= 0
      and (.refuted | type) == "number" and .refuted >= 0
      and (.diff_lines | type) == "number" and .diff_lines >= 0
    ))) as $measured_tastes
  | {n: ($paired | length),
     worker: (($paired | map(.tokens) | add) // 0),
     orchestration: (($paired | map(.claude_tokens) | add) // 0)} as $p
  | $t
  + (if $p.orchestration > 0 then {work_split: (($p.worker / $p.orchestration) | .*10 | round / 10 | tostring + "x worker:orchestrator")} else {} end)
  + (if $t.jobs > $p.n then {split_excludes_jobs: ($t.jobs - $p.n)} else {} end)
  + (if $total > $t.jobs then {unreadable_lines: ($total - $t.jobs)} else {} end)
  + (if ($measured_tastes | length) > 0 then
       {taste: {
         measured: ($measured_tastes | length),
         without_outcome: (($taste_rows | length) - ($measured_tastes | length)),
         hit_rate: ($measured_tastes | hit_rate),
         smallest_hit_diff_lines: (($measured_tastes | map(select(.confirmed >= 1) | .diff_lines) | min) // null),
         by_diff_size: [
           bucket("<=50"; $measured_tastes | map(select(.diff_lines <= 50))),
           bucket("51-200"; $measured_tastes | map(select(.diff_lines >= 51 and .diff_lines <= 200))),
           bucket("201-500"; $measured_tastes | map(select(.diff_lines >= 201 and .diff_lines <= 500))),
           bucket(">500"; $measured_tastes | map(select(.diff_lines > 500)))
         ]
       }}
     else {} end)'
