#!/usr/bin/env bash
# Render a measured, human-recorded benchmark ledger. It never runs benchmark arms.
set -u

ledger=${1:-}
if [ -n "$ledger" ]; then
  case $ledger in
    /*) ;;
    *) ledger="$(pwd)/$ledger" ;;
  esac
fi
cd "$(dirname "$0")/.."
prices=skills/receipts/references/prices.md

if [ -z "$ledger" ] || [ ! -f "$ledger" ]; then
  printf 'bench: ledger not found: %s\n' "${ledger:-<none>}" >&2
  exit 1
fi

# Validate the JSONL contract before rendering. A task can have one row for each
# arm, but cannot repeat an arm; an incomplete task is reported without a delta.
if ! jq -s -e '
  all(.[];
    type == "object" and
    (.task | type == "string" and length > 0) and
    (.arm == "delegated" or .arm == "direct") and
    (.model | type == "string" and length > 0) and
    (.orchestrator | type == "string" and length > 0) and
    (.worker_tokens | type == "number" and floor == . and . >= 0) and
    (.arm != "direct" or .worker_tokens == 0) and
    (.arm != "direct" or .model == .orchestrator) and
    (.claude_tokens | type == "number" and floor == . and . >= 0) and
    (.verified | type == "boolean") and
    (.wallclock_s | type == "number" and floor == . and . >= 0)
  ) and
  ([.[] | [.task, .arm]] | group_by(.) | all(length == 1))
' "$ledger" >/dev/null; then
  printf '%s\n' 'bench: invalid JSONL schema, duplicate task/arm row, direct arm worker_tokens is not zero, or direct arm model differs from its orchestrator' >&2
  exit 1
fi

# The fifth Markdown-table column is the existing 50/50 API-list blend. Prices
# are deliberately extracted here rather than copied into the reporter.
price_rows=$(awk -F '|' '
  /^\|/ {
    model=$2; blend=$5
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", model)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", blend)
    if (model != "Model" && model != "" && blend ~ /^[0-9]+([.][0-9]+)?$/) {
      print model "\t" blend
    }
  }
' "$prices")

python3 - "$ledger" "$price_rows" <<'PY'
import json
import sys
from collections import defaultdict
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

ledger_path, price_rows = sys.argv[1:3]
MILLION = Decimal("1000000")

prices = {}
for row in price_rows.splitlines():
    model, blend = row.split("\t", 1)
    try:
        prices[model] = Decimal(blend)
    except InvalidOperation:
        pass

with open(ledger_path, encoding="utf-8") as source:
    rows = [json.loads(line) for line in source if line.strip()]

def rounded_money(value):
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

def money(value):
    return "~$" + str(rounded_money(value))

def row_cost(row):
    # A model without a table row is unpriced even where its worker count is zero:
    # the input contract says the arm model itself must be priceable.
    if row["model"] not in prices or row["orchestrator"] not in prices:
        return None
    # Orchestration is priced at the model that actually ran it, per row. Pricing every
    # arm at one reference orchestrator would inflate a direct arm that ran a cheaper
    # Claude - and the direct arm is what delegation is measured against, so that error
    # would flatter delegation.
    # Rounded to cents once, here. Every delta and total downstream is derived from
    # the same cent figures the table prints, so no two lines of the report can
    # disagree about the same number.
    return rounded_money(
        Decimal(row["worker_tokens"]) * prices[row["model"]] / MILLION
        + Decimal(row["claude_tokens"]) * prices[row["orchestrator"]] / MILLION
    )

rows.sort(key=lambda r: (r["task"], 0 if r["arm"] == "delegated" else 1))
by_task = defaultdict(dict)
for row in rows:
    by_task[row["task"]][row["arm"]] = row

print("# expo benchmark report")
print()
print("Pricing is in API-list terms, using the 50/50 blend in `skills/receipts/references/prices.md`.")
print()
print("| task | arm | worker model | orchestrator | worker tokens | orchestration tokens | ~cost | verified | wallclock |")
print("| --- | --- | --- | --- | ---: | ---: | ---: | --- | ---: |")
for row in rows:
    cost = row_cost(row)
    if not row["verified"]:
        cost_text = "failed (excluded)"
        verified = "failed (excluded)"
    elif cost is None:
        cost_text = "UNPRICED (excluded from totals)"
        verified = "yes"
    else:
        cost_text = money(cost)
        verified = "yes"
    print(
        "| {task} | {arm} | {model} | {orch} | {worker:,} | {claude:,} | {cost} | {verified} | {wallclock:,}s |".format(
            task=row["task"], arm=row["arm"], model=row["model"],
            orch=row["orchestrator"], worker=row["worker_tokens"],
            claude=row["claude_tokens"], cost=cost_text,
            verified=verified, wallclock=row["wallclock_s"],
        )
    )

print()
print("## Measured deltas")
print()
compared = 0
totals = {"delegated": Decimal(0), "direct": Decimal(0)}
for task in sorted(by_task):
    arms = by_task[task]
    missing = [arm for arm in ("delegated", "direct") if arm not in arms]
    if missing:
        print(f"- {task}: no delta — missing {' and '.join(missing)} arm.")
        continue
    failed = [arm for arm in ("delegated", "direct") if not arms[arm]["verified"]]
    if failed:
        print(f"- {task}: no delta — {' and '.join(failed)} arm failed verification.")
        continue
    costs = {arm: row_cost(arms[arm]) for arm in ("delegated", "direct")}
    unpriced = [arm for arm, cost in costs.items() if cost is None]
    if unpriced:
        print(f"- {task}: no delta — {' and '.join(unpriced)} arm is unpriced.")
        continue
    delta = costs["direct"] - costs["delegated"]
    compared += 1
    totals["delegated"] += costs["delegated"]
    totals["direct"] += costs["direct"]
    relation = "delegated lower" if delta > 0 else "direct lower" if delta < 0 else "equal"
    print(f"- {task}: direct − delegated = {money(abs(delta))} ({relation}; observed difference on this measured task set).")

print()
delta_total = totals["direct"] - totals["delegated"]
if compared:
    relation = "delegated lower" if delta_total > 0 else "direct lower" if delta_total < 0 else "equal"
    delta_text = f"{money(abs(delta_total))} ({relation}; observed difference on this measured task set)"
else:
    delta_text = "n/a (no verified, priced task pairs)"
task_label = "task" if compared == 1 else "tasks"
print(
    f"**Aggregate:** {compared} {task_label} compared; delegated total {money(totals['delegated'])}; "
    f"direct total {money(totals['direct'])}; total observed delta (direct − delegated) {delta_text}."
)
PY
