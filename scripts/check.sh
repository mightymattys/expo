#!/usr/bin/env bash
# expo self-checks - "claims are not evidence", applied to the repo's own text.
# The value is this executable invariant list; CI just runs it (issue #8).
# Deterministic except the link sweep, which fails only on hard 404/410
# (transient codes and bot-blocks warn). SKIP_LINKS=1 skips the sweep.
set -u
cd "$(dirname "$0")/.."

fail=0
ok()   { printf 'ok   %s\n' "$1"; }
err()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }
warn() { printf 'warn %s\n' "$1"; }
section_ok() { [ "$fail" -eq "$mark" ] && ok "$1"; mark=$fail; }
mark=0

# 1. Manifest sanity ----------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  if out=$(claude plugin validate . 2>&1); then
    ok "claude plugin validate"
  else
    err "claude plugin validate:"; printf '%s\n' "$out"
  fi
else
  warn "claude CLI not installed - skipping plugin validate (CI runs it)"
fi
mark=$fail

# 1b. Release script ----------------------------------------------------------
if [ -x scripts/release.sh ]; then
  ok "scripts/release.sh is executable"
else
  err "scripts/release.sh must exist and be executable"
fi
if bash -n scripts/release.sh; then
  ok "scripts/release.sh parses"
else
  err "scripts/release.sh does not parse"
fi
# A shipped version whose entry still says "Unreleased" happened twice before the
# release script stamped the changelog itself.
if grep -q 'scripts/stamp-changelog.py' scripts/release.sh; then
  ok "release.sh stamps the changelog in the release commit"
else
  err "release.sh must stamp the changelog via scripts/stamp-changelog.py"
fi
# gh's {owner}/{repo} placeholder resolves to the UPSTREAM repo on a fork - verified
# here, where it pointed at tomascupr/sous-chef. A release must never be aimed there.
if grep -q 'repos/{owner}/{repo}' scripts/release.sh; then
  err "release.sh uses gh's {owner}/{repo} placeholder - on a fork that targets upstream; derive the slug from origin"
else
  ok "release.sh targets the origin remote, not gh's fork-aware placeholder"
fi
undated=$(grep -E '^## ' CHANGELOG.md | grep -vE '^## +Unreleased' | grep -cvE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
unreleased=$(grep -cE '^## +Unreleased' CHANGELOG.md || true)
if [ "$undated" -eq 0 ] && [ "$unreleased" -le 1 ]; then
  ok "every changelog heading is dated, at most one Unreleased"
else
  err "CHANGELOG.md has $undated undated heading(s) and $unreleased Unreleased heading(s) - a shipped version must carry its date"
fi
mark=$fail

# 2. Skill frontmatter --------------------------------------------------------
# CLAUDE.md rule: no ": " inside a description - YAML plain scalars break on it.
for f in skills/*/SKILL.md; do
  desc=$(sed -n 's/^description: //p' "$f")
  [ -n "$desc" ] || { err "$f: no description in frontmatter"; continue; }
  case $desc in
    *": "*) err "$f: ': ' inside description breaks YAML plain scalars - use ' - '" ;;
  esac
done
section_ok "skill frontmatter"

# 3. Cross-file invariants ----------------------------------------------------
# Every field a reader parses from another skill's artifact is named by its writer.
must_contain() { # file fixed-string reason
  grep -qF -- "$2" "$1" || err "$1 must contain '$2' - $3"
}
must_contain skills/serve/SKILL.md  'started:'  "the receipt template reads state.md's started: for wallclock"
must_contain skills/simmer/SKILL.md 'started:'  "the receipt template reads the branch-scoped loop file's started: for wallclock"
must_contain skills/serve/SKILL.md  'findings:' "refire (via serve) reads state.md's findings: line"
must_contain skills/serve/SKILL.md  'baseline:' "taste's post-fire scope reads state.md's baseline: line"
must_contain skills/taste/SKILL.md  'tree:'     "refire's preflight reads findings.md's tree: anchor"
must_contain skills/serve/SKILL.md  'tier:'     "refire reads state.md's tier: line for the worker tier"
must_contain skills/refire/SKILL.md 'tier:'     "refire must read the tier serve recorded"
must_contain skills/simmer/SKILL.md 'tier:'     "every Codex lap's invocation reads the branch-scoped loop file's tier: line"
must_contain skills/simmer/SKILL.md 'tier: n/a' "Sonnet loops record the tier field receipts and resumes expect"
must_contain skills/simmer/SKILL.md 'record a `worker:` line' "the loop contract fixes one worker route for every lap"
must_contain skills/fire/SKILL.md '| `opus` |' "fire's worker table names the Opus route"
must_contain skills/serve/SKILL.md 'worker: <codex | sonnet | opus>' "serve's state schema must be able to record every fire worker"
must_contain skills/fire/references/worker-routes.md 'claude-opus-5' "Opus's model id is available to the route-must-be-priceable check"
must_contain scripts/bench.sh 'observed difference on this measured task set' "both benchmark arms are measured, so the delta is a sample and must never be worded as a bound"
must_contain docs/benchmark.md 'not a bound, guarantee, or general cross-model' "the methodology has to say what the delta is not"
must_contain skills/simmer/SKILL.md 'loop-<branch-slug>' "simultaneous branches need branch-scoped loop state"
must_contain skills/simmer/SKILL.md '`/` replaced by `-` plus a 6-char suffix from a stable hash' "branch-scoped loop files cannot collide after slash replacement"
must_contain skills/simmer/SKILL.md '[../fire/references/worker-routes.md](../fire/references/worker-routes.md)' "Sonnet laps use fire's subscription invocation"
must_contain skills/simmer/SKILL.md 'git merge-base --is-ancestor' "recreated branches must not inherit stale loop state"
must_contain skills/receipts/references/receipt-template.md '.expo/loop-<branch-slug>.md' "simmer receipts read branch-scoped loop state"
# A verdict is only true of the tree it was reached against, and a receipt outlives it.
must_contain skills/receipts/references/receipt-template.md 'tree:' "a receipt records the tree its verdict was reached against"
must_contain skills/receipts/SKILL.md 'tree moved' "printing receipts marks verdicts whose tree has since moved"
# A worker inheriting a routing policy can delegate onward, unwatched.
must_contain skills/fire/references/ticket-template.md 'do not delegate' "every ticket forbids onward delegation, not just the Claude routes"
# A stale installed copy is silent; its first visible symptom is an unpriceable model.
must_contain skills/receipts/references/receipt-template.md 'INSTALLED plugin is older' "an unpriceable model points at the install, not at prices.md"
must_contain skills/mise/SKILL.md 'claude plugin update expo@expo' "mise reports the running version and offers the update"
must_contain skills/receipts/references/receipt-template.md 'filtered by `"branch":"<branch>"`' "simmer receipts select this branch's ledger laps"
if python3 - <<'PY'
lines = open("skills/serve/SKILL.md", encoding="utf-8").read().splitlines()
command = [
    '`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ledger-append.py" --run "$RUN" --session',
    '"${CLAUDE_CODE_SESSION_ID:-}"`.',
]
matches = [index for index in range(len(lines) - 1) if lines[index:index + 2] == command]
receipts = [index for index, line in enumerate(lines)
            if line == "Then write the run's receipt to `.expo/receipts/` per"]
if len(matches) != 1 or len(receipts) != 1 or matches[0] >= receipts[0]:
    raise SystemExit(1)
before = "\n".join(lines[:matches[0]])
if before.rfind("<!--") > before.rfind("-->"):
    raise SystemExit(1)
PY
then
  ok "serve runs the complete ledger sweep before writing its receipt"
else
  err "skills/serve/SKILL.md must run the complete ledger sweep before writing its receipt"
fi

# A receipt's only savings claim is explicitly qualified with a floor or bound.
while IFS= read -r line; do
  lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
  case $lower in
    *floor*|*'>='*|*'≥'*) ;;
    *) err "unqualified savings claim: $line" ;;
  esac
done < <(grep -rinE -- 'sav(e|ed|ings?)\b' skills/receipts/ || true)

must_contain README.md 'docs/benchmark.md' "the delegation FAQ links expo's benchmark method"
must_contain docs/benchmark.md 'scripts/bench.sh' "benchmark method names its reporter"

# README's inventory drifted silently once: it named one script while the repo had
# seven, and never mentioned the newest user-visible behaviour at all.
box_drift=$(python3 - <<'INVENTORY'
import os, re
text = open("README.md", encoding="utf-8").read()
match = re.search(r"## .{0,4} ?What's in the box\n\n```text\n(.*?)```", text, re.S)
if not match:
    print("README has no 'What's in the box' block")
    raise SystemExit
listed = {line.split()[0].rstrip("/") for line in match.group(1).splitlines() if line.strip()}
real = {f"skills/{name}" for name in os.listdir("skills")} | {"codex", "templates", "bench"}
for folder in ("scripts", "docs"):
    real |= {f"{folder}/{name}" for name in os.listdir(folder)
             if name.endswith((".sh", ".py", ".md"))}
for name in sorted(real - listed):
    print(f"{name} ships but README's inventory omits it")
for name in sorted(listed - real):
    print(f"README's inventory names {name}, which does not ship")
INVENTORY
)
if [ -z "$box_drift" ]; then
  ok "README's inventory matches what ships"
else
  err "README inventory drift:
$box_drift"
fi

# The published results are a render of the recorded arms at current prices. If either
# moves, the committed table is stale - and a stale table is a wrong cost claim.
if bench_render=$(bash scripts/bench.sh bench/results.jsonl 2>&1); then
  if printf '%s\n' "$bench_render" | diff -q - bench/RESULTS.md >/dev/null; then
    ok "bench/RESULTS.md matches the reporter's current output"
  else
    err "bench/RESULTS.md is stale - rerun 'scripts/bench.sh bench/results.jsonl > bench/RESULTS.md'"
  fi
else
  err "bench/results.jsonl does not render: $bench_render"
fi

# The tier names are one vocabulary, spelled identically wherever tiers are chosen.
for t in sol terra luna; do
  for f in skills/fire/SKILL.md skills/refire/SKILL.md; do
    grep -q "$t" "$f" || err "$f must name tier '$t' - fire's tier table and refire's override share one vocabulary"
  done
done

# Ledger claude_tokens windows are per-job: every job-dir mint stamps $JOB/started.
for f in skills/fire/SKILL.md skills/taste/SKILL.md skills/refire/SKILL.md skills/simmer/SKILL.md; do
  grep -qF '$JOB/started' "$f" || err "$f mints a job dir but never stamps \$JOB/started - its claude_tokens window has no anchor"
done

# Job names may be readable, but their stage prefix is the sweep's routing key.
for s in fire taste refire simmer; do
  minted="JOB=\$(mktemp -d \"\$SCRATCHPAD/$s-<label>-XXXXXX\")"
  stale="\$SCRATCHPAD/$s-XXXXXX"
  [ "$(grep -oF -- "$minted" "skills/$s/SKILL.md" | wc -l | tr -d ' ')" -eq 1 ] \
    || err "skills/$s/SKILL.md must mint its stage-prefixed, labelled job dir exactly once"
  if grep -qF -- "$stale" "skills/$s/SKILL.md"; then
    err "skills/$s/SKILL.md still permits the unlabelled job-dir form"
  fi
done
for s in fire taste refire; do
  sweep='ledger-append.py" --run "$SCRATCHPAD" --session "${CLAUDE_CODE_SESSION_ID:-}"'
  stale="--job \"\$JOB\" --skill $s"
  [ "$(grep -oF -- "$sweep" "skills/$s/SKILL.md" | wc -l | tr -d ' ')" -eq 1 ] \
    || err "skills/$s/SKILL.md must contain its session-scratchpad plating command exactly once"
  if grep -qF -- "$stale" "skills/$s/SKILL.md"; then
    err "skills/$s/SKILL.md still permits a per-job plating call"
  fi
done

# taste's reviewer pin is real, not a hope about the user's config.
must_contain skills/taste/SKILL.md '-c model=gpt-5.6-sol' "the 'taste stays on sol' claim needs an actual pin on the invocation"

# The taste/refire tree anchor is one recipe, spelled identically on both sides.
ANCHOR='$(git rev-parse --short HEAD)+$(idx=$(mktemp -u); GIT_INDEX_FILE=$idx git add -A && GIT_INDEX_FILE=$idx git write-tree | cut -c1-12)'
must_contain skills/taste/SKILL.md  "$ANCHOR" "taste writes the anchor refire recomputes"
must_contain skills/refire/SKILL.md "$ANCHOR" "refire recomputes the anchor taste writes"

# Every skill that backgrounds a worker carries the no-nested-backgrounding rule -
# literally (nohup named) or by an explicit pointer to fire's rule. Match the word
# "backgrounded" too, not just the Bash annotation: refire and simmer background
# workers by cross-reference without repeating the invocation block.
for f in $(grep -rlE 'run_in_background: true|backgrounded' skills/); do
  grep -qE 'nohup|backgrounding rule' "$f" || err "$f backgrounds a worker but carries neither the no-&/nohup/disown rule nor a pointer to fire's"
done

# Ledger writes are code, not a transcription task; every writer invokes the one
# measured appender. Simmer keeps its per-lap metadata; other stages sweep the session.
for s in fire taste refire simmer; do
  must_contain "skills/$s/SKILL.md" 'scripts/ledger-append.py' "its ledger write uses the measured appender"
done
must_contain skills/simmer/SKILL.md '--skill simmer' "simmer's per-lap write carries its own skill tag"
if grep -R -qF '{"ts":' skills/; then
  err "skills must not hand-write ledger JSON lines"
else
  ok "skills do not hand-write ledger JSON lines"
fi
if grep -R -nE '(>>|tee[[:space:]]+-a).*(~/.expo/ledger\.jsonl|ledger\.jsonl)|(~/.expo/ledger\.jsonl|ledger\.jsonl).*(>>|tee[[:space:]]+-a)' skills/ >/dev/null; then
  err "skills must not hand-roll appends to ~/.expo/ledger.jsonl"
else
  ok "skills use the appender as the sole ledger writer"
fi

# Every plugin-root path a skill or template names actually ships in the repo.
for p in $(grep -rho 'CLAUDE_PLUGIN_ROOT}/[A-Za-z0-9._/-]*' skills/ templates/ | sed 's|^CLAUDE_PLUGIN_ROOT}/||' | sort -u); do
  [ -e "$p" ] || err "\${CLAUDE_PLUGIN_ROOT}/$p is referenced but does not exist"
done

# Every relative markdown link resolves - skills/, README, and docs alike.
for f in $(find skills docs -name '*.md') README.md AGENTS.md; do
  for l in $(grep -o ']([^)]*)' "$f" | sed 's/^](//; s/)$//'); do
    case $l in http*|'#'*|../../issues/*) continue ;; esac
    [ -e "$(dirname "$f")/${l%%#*}" ] || err "$f links $l which does not exist"
  done
done
section_ok "cross-file invariants"

# 3b. Pricing freshness ---------------------------------------------------------
# prices.md is manual data; these checks make its staleness loud instead of silent.
PRICES=skills/receipts/references/prices.md
# Every Claude subscription model this plugin can fire has a price-table row. Without
# that row, receipts would silently be unable to price a route the plugin advertises.
models=$(grep -oE -- '--model[= ]+claude-[a-z0-9-]+-5' skills/fire/references/worker-routes.md | grep -oE 'claude-[a-z0-9-]+-5' | sort -u || true)
if [ -z "$models" ]; then
  err "worker-routes.md names no Claude worker models - extraction pattern broken?"
fi
for model in $models; do
  grep -qF "| $model |" "$PRICES" || err "Claude worker route '$model' has no matching prices.md row"
done
asof=$(sed -n 's/.*checked \([0-9-]*\).*/\1/p' "$PRICES" | head -1)
if [ -n "$asof" ]; then
  age=$(python3 -c "from datetime import date; print((date.today() - date.fromisoformat('$asof')).days)" 2>/dev/null)
  if [ -n "$age" ] && [ "$age" -gt 45 ]; then
    err "prices.md as-of date ($asof) is $age days old - re-verify list prices and bump the date"
  elif [ -n "$age" ] && [ "$age" -gt 30 ]; then
    warn "prices.md as-of date ($asof) is $age days old - consider re-verifying"
  fi
else
  err "prices.md carries no parseable 'checked YYYY-MM-DD' as-of date"
fi
# Date-bound notes ("through YYYY-MM-DD") must not silently outlive their window.
for d in $(grep -oE 'through [0-9]{4}-[0-9]{2}-[0-9]{2}' "$PRICES" | grep -oE '[0-9-]+$'); do
  expired=$(python3 -c "from datetime import date; print(1 if date.today() > date.fromisoformat('$d') else 0)" 2>/dev/null)
  [ "$expired" = 1 ] && err "prices.md has a 'through $d' note that has expired - the row it qualifies is now wrong"
done
section_ok "pricing freshness"

# 3c. Measurement scripts -----------------------------------------------------
if python3 -c 'import ast; ast.parse(open("scripts/stamp-changelog.py").read())'; then
  ok "scripts/stamp-changelog.py parses"
else
  err "scripts/stamp-changelog.py does not parse"
fi
if python3 -c 'import ast; ast.parse(open("scripts/diffscan.py").read())'; then
  ok "scripts/diffscan.py parses"
else
  err "scripts/diffscan.py does not parse"
fi
DIFFSCAN_EXPECTED=$(mktemp)
cat > "$DIFFSCAN_EXPECTED" <<'EOF'
## Change scan

- 8 files changed, +9/-22
- by path pattern: config 2, generated 1, docs 1, source 3, tests 1
- new files 1, deleted 1, renamed 1

### Manifest-line matches
- Pattern list: manifest-line regular expressions
- package.json: +1/-1 matched lines

### Removed-line matches
- Pattern list: removed-line substrings (case-insensitive)
- src/gone.py:-raise Gone()
- src/pay.ts:-} catch (err) {
- src/pay.ts:-  except Error:
- src/pay.ts:-  finally:
- src/pay.ts:-  rescue StandardError
- src/pay.ts:-  throw error
- src/pay.ts:-  raise Error()
- src/pay.ts:-  assert ready
- src/pay.ts:-  validate(data)
- src/pay.ts:-  if err != nil {
- src/pay.ts:-  panic("bad")
- src/pay.ts:-  authorize(user)
- src/pay.ts:-  authenticate(user)
- src/pay.ts:-  permission = false
- src/pay.ts:-  sanitize(input)
- ... and 2 more

### Test-pattern matches
- Pattern list: test-pattern substrings (case-sensitive)
- +3/-1 matched lines
EOF
if python3 scripts/diffscan.py --min-lines 1 scripts/fixtures/diffscan.diff | diff -u "$DIFFSCAN_EXPECTED" - >/dev/null; then
  ok "diffscan.py reports the fixture exactly"
else
  err "diffscan.py fixture output differs:"; python3 scripts/diffscan.py --min-lines 1 scripts/fixtures/diffscan.diff
fi
# Every fixture is pinned to its full expected output, not a few greps. A loose
# assertion is how the empty-file blocker and a corrupt fixture both survived a run.
for fixture in scripts/fixtures/*.diff; do
  expected="${fixture%.diff}.expected"
  if [ ! -f "$expected" ]; then
    err "$fixture has no golden $expected - every fixture pins its full output"
    continue
  fi
  if actual=$(python3 scripts/diffscan.py --min-lines 0 "$fixture" 2>&1) &&
    printf '%s\n' "$actual" | diff -q - "$expected" >/dev/null; then
    ok "diffscan.py matches the golden output for $(basename "$fixture")"
  else
    err "diffscan.py output differs from $expected:
$(printf '%s\n' "$actual" | diff - "$expected" | head -12)"
  fi
done
# A golden file with no fixture beside it is a leftover that pins nothing.
for expected in scripts/fixtures/*.expected; do
  fixture="${expected%.expected}"
  [ -f "$fixture.diff" ] || [ -f "$fixture.log" ] || err "$expected has no fixture beside it"
done

if python3 scripts/diffscan.py --min-lines 1 scripts/fixtures/diffscan-paths.diff | grep -Fx -- '- 2 files changed, +2/-2' >/dev/null; then
  ok "diffscan.py reads spaced and C-quoted Git paths"
else
  err "diffscan.py must read spaced and C-quoted Git paths"
fi
if [ "$(python3 scripts/diffscan.py --min-lines 0 scripts/fixtures/diffscan-combined.diff)" = '- 1 combined diff entries were not line-counted' ]; then
  ok "diffscan.py reports combined diffs without invented totals"
else
  err "diffscan.py must report combined diffs separately"
fi
if [ "$(printf '%s\n' 'diff --git a/broken.py b/broken.py' '@@ unreadable hunk' | python3 scripts/diffscan.py --min-lines 0 -)" = '- 1 diff entries were unreadable' ]; then
  ok "diffscan.py suppresses zero totals when every entry is skipped"
else
  err "diffscan.py must suppress zero totals when every entry is skipped"
fi
out=$(python3 scripts/diffscan.py scripts/fixtures/no-such.diff 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -Fx "diffscan: cannot read 'scripts/fixtures/no-such.diff': No such file or directory" >/dev/null; then
  ok "diffscan.py reports unreadable input"
else
  err "diffscan.py must reject unreadable input (rc $rc): $out"
fi
out=$(python3 scripts/diffscan.py --min-lines -1 - 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = 'diffscan: --min-lines must be a non-negative integer' ]; then
  ok "diffscan.py reports invalid arguments"
else
  err "diffscan.py must reject invalid arguments (rc $rc): $out"
fi
if [ -z "$(python3 scripts/diffscan.py scripts/fixtures/diffscan.diff)" ] \
  && [ -z "$(printf 'not a diff\n' | python3 scripts/diffscan.py --min-lines 1 -)" ]; then
  ok "diffscan.py drops below-threshold and malformed input"
else
  err "diffscan.py must drop below-threshold and malformed input"
fi
for f in scripts/fixtures/*.diff; do
  if [ "$(basename "$f")" = diffscan-combined.diff ]; then
    if ! git apply --stat "$f" >/dev/null 2>&1; then
      ok "diffscan combined fixture is the documented git-apply exception"
    else
      err "$f must remain a standalone git-apply exception"
    fi
  elif git apply --stat "$f" >/dev/null 2>&1; then
    ok "git apply --stat accepts $f"
  else
    err "git apply --stat rejects $f"
  fi
done
rm -f "$DIFFSCAN_EXPECTED"
STAMP_FIX=$(mktemp)
today=$(date -u +%F)
stamp_case() { # heading, version, expected-heading-or-FAIL
  printf '%s\n\n- entry.\n' "$1" > "$STAMP_FIX"
  before=$(cat "$STAMP_FIX")
  out=$(python3 scripts/stamp-changelog.py "$2" "$STAMP_FIX" 2>&1)
  rc=$?
  if [ "$3" = FAIL ]; then
    if [ "$rc" -eq 1 ] && [ "$before" = "$(cat "$STAMP_FIX")" ]; then
      ok "stamp-changelog.py refuses: $1"
    else
      err "stamp-changelog.py should have refused '$1' and left the file untouched (rc $rc): $out"
    fi
  elif [ "$rc" -eq 0 ] && [ "$out" = "$3" ] && head -1 "$STAMP_FIX" | grep -Fx "$3" >/dev/null; then
    ok "stamp-changelog.py stamps: $1"
  else
    err "stamp-changelog.py expected '$3' for '$1' (rc $rc), got '$out'"
  fi
}
stamp_case '## Unreleased - 0.7.13 - a title' 0.7.13 "## 0.7.13 - $today - a title"
stamp_case '## Unreleased - 0.7.13' 0.7.13 "## 0.7.13 - $today"
stamp_case '## Unreleased' 0.7.13 "## 0.7.13 - $today"
stamp_case '## Unreleased - a title with no version' 0.7.13 "## 0.7.13 - $today - a title with no version"
stamp_case '## Unreleased - 0.9.9 - wrong version' 0.7.13 FAIL
stamp_case '## 0.7.12 - 2026-07-27' 0.7.13 FAIL
rm -f "$STAMP_FIX"

if [ -x scripts/orch-tokens.py ]; then
  ok "scripts/orch-tokens.py is executable"
else
  err "scripts/orch-tokens.py must exist and be executable"
fi
if python3 -c 'import ast; ast.parse(open("scripts/orch-tokens.py").read())'; then
  ok "scripts/orch-tokens.py parses"
else
  err "scripts/orch-tokens.py does not parse"
fi
if python3 -c 'import ast; ast.parse(open("scripts/ledger-append.py").read())'; then
  ok "scripts/ledger-append.py parses"
else
  err "scripts/ledger-append.py does not parse"
fi
if [ -x scripts/tab.sh ]; then
  ok "scripts/tab.sh is executable"
else
  err "scripts/tab.sh must exist and be executable"
fi
if bash -n scripts/tab.sh; then
  ok "scripts/tab.sh parses"
else
  err "scripts/tab.sh does not parse"
fi
if [ -x scripts/bench.sh ]; then
  ok "scripts/bench.sh is executable"
else
  err "scripts/bench.sh must exist and be executable"
fi
if bash -n scripts/bench.sh; then
  ok "scripts/bench.sh parses"
else
  err "scripts/bench.sh does not parse"
fi

FIXHOME=$(mktemp -d)
mkdir -p "$FIXHOME/projects/-fixture"
printf '%s\n' \
  '{"type":"user","timestamp":"2026-01-01T00:00:00Z"}' \
  '{"type":"assistant","timestamp":"2026-01-01T00:00:00Z","message":{"usage":{"input_tokens":5,"output_tokens":5}}}' \
  '{"type":"assistant","timestamp":"2026-01-02T00:00:00Z","message":{"usage":{"input_tokens":2,"output_tokens":2}}}' \
  '{"type":"assistant","timestamp":"2026-01-02T00:00:00.500Z","message":{"usage":{"input_tokens":100,"output_tokens":40}}}' \
  '{"type":"assistant","timestamp":"2026-01-03T00:00:00Z","message":{"usage":{"input_tokens":10,"output_tokens":1}}}' \
  > "$FIXHOME/projects/-fixture/aaaa-bbbb.jsonl"

out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/orch-tokens.py aaaa-bbbb 2026-01-02T00:00:00Z)
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = 155 ] && ok "orch-tokens.py sums fixture window inclusively" || err "orch-tokens.py fixture window expected rc 0 and 155, got rc $rc and '$out'"
out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/orch-tokens.py aaaa-bbbb 2027-01-01T00:00:00Z)
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "orch-tokens.py drops empty fixture window" || err "orch-tokens.py empty fixture window expected rc 0 and no output, got rc $rc and '$out'"
out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/orch-tokens.py aaaa-bbbb 2026-01-02T00:00:00Z 2026-01-03T00:00:00Z)
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = 144 ] && ok "orch-tokens.py honors fixture upper bound" || err "orch-tokens.py bounded fixture window expected rc 0 and 144, got rc $rc and '$out'"

printf '%s\n' \
  '{"type":"assistant","timestamp":"2026-01-02T00:00:00Z","message":{"usage":null}}' \
  > "$FIXHOME/projects/-fixture/usage-null.jsonl"
out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/orch-tokens.py usage-null 2026-01-02T00:00:00Z)
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "orch-tokens.py drops invalid usage" || err "orch-tokens.py invalid usage expected rc 0 and no output, got rc $rc and '$out'"

mkdir -p "$FIXHOME/projects/-fixture-duplicate"
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-02T00:00:00Z","message":{"usage":{"input_tokens":1,"output_tokens":1}}}' \
  > "$FIXHOME/projects/-fixture/two-match.jsonl"
cp "$FIXHOME/projects/-fixture/two-match.jsonl" "$FIXHOME/projects/-fixture-duplicate/two-match.jsonl"
out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/orch-tokens.py two-match 2026-01-02T00:00:00Z)
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "orch-tokens.py drops ambiguous transcript matches" || err "orch-tokens.py ambiguous matches expected rc 0 and no output, got rc $rc and '$out'"

TAB_LEDGER=$(mktemp)
printf '%s\n' \
  '{"tokens":20,"claude_tokens":10}' \
  '{"tokens":30}' \
  > "$TAB_LEDGER"
tab=$(bash scripts/tab.sh "$TAB_LEDGER")
rc=$?
# 20/10 on the paired line, NOT 50/10 across both: the unpaired line's 30 worker
# tokens have no denominator, and folding them in as zero is what reported 5.1x on a
# ledger whose like-for-like split was 2.8x.
if [ "$rc" -eq 0 ] && printf '%s' "$tab" | jq -e '.jobs == 2 and .worker_tokens == 50 and .orchestration_tokens == 10 and .work_split == "2x worker:orchestrator" and .split_excludes_jobs == 1' >/dev/null; then
  ok "tab.sh splits like for like and counts the jobs it excluded"
else
  err "tab.sh fixture totals or work split are wrong (rc $rc): $tab"
fi

LEDGER_FIX=$(mktemp -d)
mkdir "$LEDGER_FIX/job"
cp scripts/fixtures/ledger-complete.log "$LEDGER_FIX/job/job.log"
out=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/job" --skill fire --repo fixture --ledger "$LEDGER_FIX/ledger.jsonl")
rc=$?
normal=$(printf '%s\n' "$out" | sed -E 's/"ts":"[^"]+"/"ts":"<ts>"/')
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$LEDGER_FIX/ledger.jsonl")" -eq 1 ] &&
  [ "$(cat "$LEDGER_FIX/job/.ledgered")" = "$out" ] &&
  printf '%s\n' "$normal" | diff -q scripts/fixtures/ledger-complete.expected - >/dev/null; then
  ok "ledger-append.py writes the complete fixture and its exact marker"
else
  err "ledger-append.py complete fixture expected one golden line (rc $rc): $out"
fi
if python3 -m json.tool "$LEDGER_FIX/ledger.jsonl" >/dev/null; then
  ok "ledger-append.py strips token separators into parseable JSON"
else
  err "ledger-append.py wrote invalid JSON for a comma-separated token summary"
fi
out=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/job" --skill fire \
  --repo fixture --ledger "$LEDGER_FIX/ledger.jsonl" 2>"$LEDGER_FIX/repeated-job.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] &&
  [ "$(wc -l < "$LEDGER_FIX/ledger.jsonl")" -eq 1 ] &&
  grep -Fxq "ledger-append: skipped already ledgered job dir: $LEDGER_FIX/job" \
    "$LEDGER_FIX/repeated-job.stderr"; then
  ok "ledger-append.py --job honours its marker and appends exactly once"
else
  err "ledger-append.py repeated --job must be a legible no-op (rc $rc): $out"
fi
tab=$(bash scripts/tab.sh "$LEDGER_FIX/ledger.jsonl")
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$tab" | jq -e '.jobs == 1 and .worker_tokens == 156605' >/dev/null; then
  ok "tab.sh renders a ledger produced by ledger-append.py"
else
  err "tab.sh cannot render the ledger-append.py fixture (rc $rc): $tab"
fi
for fixture in ledger-no-summary ledger-no-banner; do
  mkdir "$LEDGER_FIX/$fixture"
  cp "scripts/fixtures/$fixture.log" "$LEDGER_FIX/$fixture/job.log"
  out=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/$fixture" --skill fire --repo fixture --ledger "$LEDGER_FIX/$fixture.jsonl")
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -e "$LEDGER_FIX/$fixture.jsonl" ] &&
    [ ! -e "$LEDGER_FIX/$fixture/.ledgered" ]; then
    ok "ledger-append.py drops $fixture fixture without output"
  else
    err "ledger-append.py must drop $fixture fixture without output (rc $rc): $out"
  fi
done
for fixture in ledger-echoed-ticket-spoof ledger-malformed-grouping; do
  mkdir "$LEDGER_FIX/$fixture"
  cp "scripts/fixtures/$fixture.log" "$LEDGER_FIX/$fixture/job.log"
  out=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/$fixture" --skill fire --repo fixture --ledger "$LEDGER_FIX/$fixture.jsonl")
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -e "$LEDGER_FIX/$fixture.jsonl" ] &&
    [ ! -e "$LEDGER_FIX/$fixture/.ledgered" ]; then
    ok "ledger-append.py rejects $fixture fixture without output"
  else
    err "ledger-append.py must reject $fixture fixture without output (rc $rc): $out"
  fi
done
mkdir "$LEDGER_FIX/ledger-write-fails"
cp scripts/fixtures/ledger-complete.log "$LEDGER_FIX/ledger-write-fails/job.log"
out=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/ledger-write-fails" --skill fire \
  --repo fixture --ledger "$LEDGER_FIX" 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$LEDGER_FIX/ledger-write-fails/.ledgered" ]; then
  ok "ledger-append.py does not mark a failed ledger write"
else
  err "ledger-append.py must not mark a failed ledger write (rc $rc): $out"
fi
mkdir "$LEDGER_FIX/ledger-final-message-spoof"
cp scripts/fixtures/ledger-final-message-spoof.log "$LEDGER_FIX/ledger-final-message-spoof/job.log"
# No trailing newline: Codex writes result.md exactly as the log's final message minus
# the log's own line ending. A fixture that adds one lets a suffix match pass here and
# fail on every real job log.
printf '%s\n%s\n%s\n%s' 'The run is complete.' 'model: final-message-model' 'tokens used' '999,999' > "$LEDGER_FIX/ledger-final-message-spoof/result.md"
out=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/ledger-final-message-spoof" --skill fire --repo fixture --ledger "$LEDGER_FIX/ledger-final-message-spoof.jsonl")
rc=$?
normal=$(printf '%s\n' "$out" | sed -E 's/"ts":"[^"]+"/"ts":"<ts>"/')
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$LEDGER_FIX/ledger-final-message-spoof.jsonl")" -eq 1 ] &&
  printf '%s\n' "$normal" | diff -q scripts/fixtures/ledger-final-message-spoof.expected - >/dev/null; then
  ok "ledger-append.py records the real summary before a final-message spoof"
else
  err "ledger-append.py must record the real summary before a final-message spoof (rc $rc): $out"
fi
mkdir "$LEDGER_FIX/simmer"
cp scripts/fixtures/ledger-complete.log "$LEDGER_FIX/simmer/job.log"
out=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/simmer" --skill simmer --lap 3 \
  --branch feat/loop --repo fixture --ledger "$LEDGER_FIX/simmer.jsonl" 2>/dev/null)
rc=$?
# A lap row the receipt cannot attribute is a lap lost to the tab: receipts filter
# simmer rows by "branch", so both fields have to survive the write, in this order.
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.skill == "simmer" and .lap == 3 and .branch == "feat/loop"' >/dev/null &&
  printf '%s' "$out" | grep -Fq '"tokens":156605,"lap":3,"branch":"feat/loop"'; then
  ok "ledger-append.py writes a simmer lap with its lap and branch"
else
  err "ledger-append.py simmer lap row is wrong (rc $rc): $out"
fi

# An omitted claude_tokens is honest; an omitted one with no reason on stderr is how
# 42% of a real ledger lost the field with nobody able to say which step failed.
mkdir "$LEDGER_FIX/why"
cp scripts/fixtures/ledger-complete.log "$LEDGER_FIX/why/job.log"
stderr=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/why" --skill fire \
  --repo fixture --ledger "$LEDGER_FIX/why.jsonl" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 0 ] && [ "$(jq -r 'has("claude_tokens")' < "$LEDGER_FIX/why.jsonl")" = false ] &&
  printf '%s' "$stderr" | grep -q 'orchestration tokens not measured'; then
  ok "ledger-append.py names the reason when orchestration goes unmeasured"
else
  err "ledger-append.py must say why claude_tokens was omitted (rc $rc): $stderr"
fi

SWEEP_RUN="$LEDGER_FIX/sweep-run"
SWEEP_LEDGER="$LEDGER_FIX/sweep.jsonl"
mkdir -p "$SWEEP_RUN"/{fire-AbC123,taste-Xy9876,refire-Q4w5e6,simmer-L0oP9q}
for job in "$SWEEP_RUN"/*; do
  cp scripts/fixtures/ledger-complete.log "$job/job.log"
done
out=$(python3 scripts/ledger-append.py --run "$SWEEP_RUN" --repo fixture \
  --ledger "$SWEEP_LEDGER" 2>"$LEDGER_FIX/sweep.stderr")
rc=$?
skills=$(jq -r '.skill' "$SWEEP_LEDGER" 2>/dev/null | sort | tr '\n' ' ')
if [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^{' || true)" -eq 3 ] &&
  [ "$(wc -l < "$SWEEP_LEDGER")" -eq 3 ] &&
  [ "$skills" = 'fire refire taste ' ] &&
  [ "$(find "$SWEEP_RUN" -name .ledgered | wc -l | tr -d ' ')" -eq 3 ] &&
  grep -Fq 'laps are ledgered per lap with --lap and --branch' "$LEDGER_FIX/sweep.stderr" &&
  grep -Fq 'sweep skipped 1 job dir(s)' "$LEDGER_FIX/sweep.stderr"; then
  ok "ledger-append.py sweeps stages but names and skips unattributable simmer laps"
else
  err "ledger-append.py recognised-stage sweep is wrong (rc $rc, skills '$skills'): $out"
fi
out=$(python3 scripts/ledger-append.py --run "$SWEEP_RUN" --repo fixture \
  --ledger "$SWEEP_LEDGER" 2>"$LEDGER_FIX/sweep-again.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(wc -l < "$SWEEP_LEDGER")" -eq 3 ] &&
  [ "$(grep -c 'skipped already ledgered job dir' "$LEDGER_FIX/sweep-again.stderr")" -eq 3 ] &&
  grep -Fq 'sweep skipped 4 job dir(s)' "$LEDGER_FIX/sweep-again.stderr"; then
  ok "ledger-append.py sweep is idempotent and names marker skips"
else
  err "ledger-append.py second sweep must be a legible no-op (rc $rc): $out"
fi

SCRATCHPAD_BARE="$LEDGER_FIX/scratchpad-bare"
mkdir -p "$SCRATCHPAD_BARE"/{fire-cenik-AbC123,taste-draft-OFfRm1}
for job in "$SCRATCHPAD_BARE"/*; do
  cp scripts/fixtures/ledger-complete.log "$job/job.log"
done
out=$(python3 scripts/ledger-append.py --run "$SCRATCHPAD_BARE" --repo fixture \
  --ledger "$LEDGER_FIX/scratchpad-bare.jsonl" 2>"$LEDGER_FIX/scratchpad-bare.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$LEDGER_FIX/scratchpad-bare.jsonl")" -eq 2 ] &&
  [ "$(jq -r .skill "$LEDGER_FIX/scratchpad-bare.jsonl" | sort | tr '\n' ' ')" = 'fire taste ' ]; then
  ok "ledger-append.py sweeps bare stage-prefixed scratchpad jobs"
else
  err "ledger-append.py bare scratchpad sweep is wrong (rc $rc): $out"
fi

SCRATCHPAD_SERVE="$LEDGER_FIX/scratchpad-serve"
mkdir -p "$SCRATCHPAD_SERVE/serve-XyZ987"/{fire-picker-OV0Asj,refire-varianty-RykTK2}
for job in "$SCRATCHPAD_SERVE/serve-XyZ987"/*; do
  cp scripts/fixtures/ledger-complete.log "$job/job.log"
done
out=$(python3 scripts/ledger-append.py --run "$SCRATCHPAD_SERVE" --repo fixture \
  --ledger "$LEDGER_FIX/scratchpad-serve.jsonl" 2>"$LEDGER_FIX/scratchpad-serve.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$LEDGER_FIX/scratchpad-serve.jsonl")" -eq 2 ] &&
  [ "$(jq -r .skill "$LEDGER_FIX/scratchpad-serve.jsonl" | sort | tr '\n' ' ')" = 'fire refire ' ]; then
  ok "ledger-append.py descends one level into a serve run in a scratchpad"
else
  err "ledger-append.py serve scratchpad descent is wrong (rc $rc): $out"
fi

SCRATCHPAD_MIXED="$LEDGER_FIX/scratchpad-mixed"
mkdir -p "$SCRATCHPAD_MIXED/fire-pasma-hUDSeU" \
  "$SCRATCHPAD_MIXED/serve-QwErTy"/{taste-machop-f7jq4G,refire-no-start-azerty} \
  "$SCRATCHPAD_MIXED/whatever-Q9"
cp scripts/fixtures/ledger-complete.log "$SCRATCHPAD_MIXED/fire-pasma-hUDSeU/job.log"
cp scripts/fixtures/ledger-complete.log "$SCRATCHPAD_MIXED/serve-QwErTy/taste-machop-f7jq4G/job.log"
cp scripts/fixtures/ledger-complete.log "$SCRATCHPAD_MIXED/serve-QwErTy/refire-no-start-azerty/job.log"
printf '%s\n' '2026-01-02T00:00:00Z' > "$SCRATCHPAD_MIXED/fire-pasma-hUDSeU/started"
printf '%s\n' '2026-01-02T00:00:00.500Z' > "$SCRATCHPAD_MIXED/serve-QwErTy/taste-machop-f7jq4G/started"
out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/ledger-append.py --run "$SCRATCHPAD_MIXED" \
  --session aaaa-bbbb \
  --ledger "$LEDGER_FIX/scratchpad-mixed.jsonl" 2>"$LEDGER_FIX/scratchpad-mixed.stderr")
rc=$?
mixed_unbounded=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/orch-tokens.py aaaa-bbbb 2026-01-02T00:00:00Z)
mixed_total=$(jq -s 'map(select(.claude_tokens != null) | .claude_tokens) | add' "$LEDGER_FIX/scratchpad-mixed.jsonl" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$LEDGER_FIX/scratchpad-mixed.jsonl")" -eq 3 ] &&
  [ "$(jq -r .skill "$LEDGER_FIX/scratchpad-mixed.jsonl" | sort | tr '\n' ' ')" = 'fire refire taste ' ] &&
  jq -e 'select(.skill == "fire") | .claude_tokens == 4' "$LEDGER_FIX/scratchpad-mixed.jsonl" >/dev/null &&
  jq -e 'select(.skill == "taste") | .claude_tokens == 151' "$LEDGER_FIX/scratchpad-mixed.jsonl" >/dev/null &&
  jq -e 'select(.skill == "refire") | has("claude_tokens") | not' "$LEDGER_FIX/scratchpad-mixed.jsonl" >/dev/null &&
  [ "$mixed_total" = "$mixed_unbounded" ] &&
  grep -Fq 'no started stamp in the job dir - orchestration tokens not measured' "$LEDGER_FIX/scratchpad-mixed.stderr" &&
  grep -Fq "$SCRATCHPAD_MIXED/whatever-Q9" "$LEDGER_FIX/scratchpad-mixed.stderr"; then
  ok "ledger-append.py partitions mixed scratchpad orchestration windows and names unknown prefixes"
else
  err "ledger-append.py mixed scratchpad windows must partition the unbounded total (rc $rc): $out"
fi
out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/ledger-append.py --run "$SCRATCHPAD_MIXED" \
  --session aaaa-bbbb \
  --ledger "$LEDGER_FIX/scratchpad-mixed.jsonl" 2>"$LEDGER_FIX/scratchpad-mixed-again.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] &&
  [ "$(wc -l < "$LEDGER_FIX/scratchpad-mixed.jsonl")" -eq 3 ] &&
  [ "$(grep -c 'skipped already ledgered job dir' "$LEDGER_FIX/scratchpad-mixed-again.stderr")" -eq 3 ]; then
  ok "ledger-append.py scratchpad sweep is idempotent"
else
  err "ledger-append.py second scratchpad sweep must append nothing (rc $rc): $out"
fi

REPO_SCRATCHPAD="$LEDGER_FIX/repo-scratchpad"
mkdir -p "$REPO_SCRATCHPAD"/{fire-first,taste-second}
sed 's|/Users/matty/Developer/expo|/Users/matty/Developer/first-repo|' \
  scripts/fixtures/ledger-complete.log > "$REPO_SCRATCHPAD/fire-first/job.log"
sed 's|/Users/matty/Developer/expo|/Users/matty/Developer/second-repo|' \
  scripts/fixtures/ledger-complete.log > "$REPO_SCRATCHPAD/taste-second/job.log"
out=$(python3 scripts/ledger-append.py --run "$REPO_SCRATCHPAD" \
  --ledger "$LEDGER_FIX/repo-scratchpad.jsonl" 2>"$LEDGER_FIX/repo-scratchpad.stderr")
rc=$?
if [ "$rc" -eq 0 ] &&
  [ "$(jq -r 'select(.skill == "fire") | .repo' "$LEDGER_FIX/repo-scratchpad.jsonl")" = first-repo ] &&
  [ "$(jq -r 'select(.skill == "taste") | .repo' "$LEDGER_FIX/repo-scratchpad.jsonl")" = second-repo ]; then
  ok "ledger-append.py resolves each swept job's repo from its own banner"
else
  err "ledger-append.py must resolve each swept job's repo from its own banner (rc $rc): $out"
fi

NO_REPO_JOB="$LEDGER_FIX/no-repo"
mkdir "$NO_REPO_JOB"
sed '/^workdir:/d' scripts/fixtures/ledger-complete.log > "$NO_REPO_JOB/job.log"
out=$(python3 scripts/ledger-append.py --job "$NO_REPO_JOB" --skill fire \
  --ledger "$LEDGER_FIX/no-repo.jsonl" 2>"$LEDGER_FIX/no-repo.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -e "$LEDGER_FIX/no-repo.jsonl" ] &&
  [ ! -e "$NO_REPO_JOB/.ledgered" ] &&
  grep -Fq 'cannot resolve repo name' "$LEDGER_FIX/no-repo.stderr"; then
  ok "ledger-append.py skips a job with no repo instead of marking it ledgered"
else
  err "ledger-append.py must skip an unresolvable repo without a marker (rc $rc): $out"
fi

MARKED_RUN="$LEDGER_FIX/marked-run"
mkdir -p "$MARKED_RUN"/{fire-Marked,taste-Fresh}
for job in "$MARKED_RUN"/*; do
  cp scripts/fixtures/ledger-complete.log "$job/job.log"
done
: > "$MARKED_RUN/fire-Marked/.ledgered"
out=$(python3 scripts/ledger-append.py --run "$MARKED_RUN" --repo fixture \
  --ledger "$LEDGER_FIX/marked.jsonl" 2>"$LEDGER_FIX/marked.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$LEDGER_FIX/marked.jsonl")" -eq 1 ] &&
  [ "$(jq -r .skill "$LEDGER_FIX/marked.jsonl")" = taste ] &&
  grep -Fq 'fire-Marked' "$LEDGER_FIX/marked.stderr"; then
  ok "ledger-append.py conservatively skips an empty marker and lands other jobs"
else
  err "ledger-append.py marked-job sweep is wrong (rc $rc): $out"
fi

MIXED_RUN="$LEDGER_FIX/mixed-run"
mkdir -p "$MIXED_RUN"/{audit-Unknown,refire-Known}
cp scripts/fixtures/ledger-complete.log "$MIXED_RUN/audit-Unknown/job.log"
cp scripts/fixtures/ledger-complete.log "$MIXED_RUN/refire-Known/job.log"
out=$(python3 scripts/ledger-append.py --run "$MIXED_RUN" --repo fixture \
  --ledger "$LEDGER_FIX/mixed.jsonl" 2>"$LEDGER_FIX/mixed.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$LEDGER_FIX/mixed.jsonl")" -eq 1 ] &&
  [ "$(jq -r .skill "$LEDGER_FIX/mixed.jsonl")" = refire ] &&
  grep -Fq 'audit-Unknown' "$LEDGER_FIX/mixed.stderr" &&
  grep -Fq 'sweep skipped 1 job dir(s)' "$LEDGER_FIX/mixed.stderr"; then
  ok "ledger-append.py names unknown prefixes and still lands recognised jobs"
else
  err "ledger-append.py unknown-prefix sweep is wrong (rc $rc): $out"
fi

BROKEN_RUN="$LEDGER_FIX/broken-run"
mkdir -p "$BROKEN_RUN"/{fire-Aborted,refire-Good}
cp scripts/fixtures/ledger-complete.log "$BROKEN_RUN/refire-Good/job.log"
out=$(python3 scripts/ledger-append.py --run "$BROKEN_RUN" --repo fixture \
  --ledger "$LEDGER_FIX/broken.jsonl" 2>"$LEDGER_FIX/broken.stderr")
rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l < "$LEDGER_FIX/broken.jsonl")" -eq 1 ] &&
  [ "$(jq -r .skill "$LEDGER_FIX/broken.jsonl")" = refire ] &&
  grep -Fq "job log not found: $BROKEN_RUN/fire-Aborted/job.log" "$LEDGER_FIX/broken.stderr" &&
  grep -Fq 'sweep skipped 1 job dir(s)' "$LEDGER_FIX/broken.stderr"; then
  ok "ledger-append.py sweep skips a broken first job and lands the later one"
else
  err "ledger-append.py broken-first sweep must continue with rc 0 (rc $rc): $out"
fi

FATAL_RUN="$LEDGER_FIX/fatal-run"
mkdir -p "$FATAL_RUN/fire-Complete" "$LEDGER_FIX/sweep-ledger-dir"
cp scripts/fixtures/ledger-complete.log "$FATAL_RUN/fire-Complete/job.log"
out=$(python3 scripts/ledger-append.py --run "$FATAL_RUN" --repo fixture \
  --ledger "$LEDGER_FIX/sweep-ledger-dir" 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$FATAL_RUN/fire-Complete/.ledgered" ] &&
  printf '%s' "$out" | grep -Fq "cannot write ledger: $LEDGER_FIX/sweep-ledger-dir"; then
  ok "ledger-append.py sweep stops when the ledger itself cannot be written"
else
  err "ledger-append.py sweep ledger failure must be fatal (rc $rc): $out"
fi

BOUNDED_RUN="$LEDGER_FIX/serve-bounded-run"
mkdir -p "$BOUNDED_RUN"/{fire-Zlatername,refire-Aearliername}
for job in "$BOUNDED_RUN"/*; do
  cp scripts/fixtures/ledger-complete.log "$job/job.log"
done
printf '%s\n' '2026-01-02T00:00:00Z' > "$BOUNDED_RUN/fire-Zlatername/started"
printf '%s\n' '2026-01-03T00:00:00Z' > "$BOUNDED_RUN/refire-Aearliername/started"
out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/ledger-append.py --run "$BOUNDED_RUN" \
  --session aaaa-bbbb --repo fixture --ledger "$LEDGER_FIX/bounded.jsonl" \
  2>"$LEDGER_FIX/bounded.stderr")
rc=$?
if [ "$rc" -eq 0 ] &&
  jq -e 'select(.skill == "fire") | .claude_tokens == 144' "$LEDGER_FIX/bounded.jsonl" >/dev/null &&
  jq -e 'select(.skill == "refire") | .claude_tokens == 11' "$LEDGER_FIX/bounded.jsonl" >/dev/null &&
  [ "$(jq -r .skill "$LEDGER_FIX/bounded.jsonl" | tr '\n' ' ')" = 'fire refire ' ]; then
  ok "ledger-append.py sweep orders started stamps and passes the next one as the upper bound"
else
  err "ledger-append.py swept orchestration windows overlap or sort by name (rc $rc): $out"
fi

MISSING_BOUND_RUN="$LEDGER_FIX/serve-missing-bound-run"
mkdir -p "$MISSING_BOUND_RUN"/{fire-First,taste-Missing}
for job in "$MISSING_BOUND_RUN"/*; do
  cp scripts/fixtures/ledger-complete.log "$job/job.log"
done
printf '%s\n' '2026-01-02T00:00:00Z' > "$MISSING_BOUND_RUN/fire-First/started"
out=$(EXPO_CLAUDE_HOME="$FIXHOME" python3 scripts/ledger-append.py --run "$MISSING_BOUND_RUN" \
  --session aaaa-bbbb --repo fixture --ledger "$LEDGER_FIX/missing-bound.jsonl" \
  2>"$LEDGER_FIX/missing-bound.stderr")
rc=$?
if [ "$rc" -eq 0 ] &&
  [ "$(jq -r 'has("claude_tokens")' "$LEDGER_FIX/missing-bound.jsonl" | sort -u)" = false ] &&
  grep -Fq 'no started stamp in the next job dir - orchestration tokens not measured' \
    "$LEDGER_FIX/missing-bound.stderr"; then
  ok "ledger-append.py omits swept orchestration when the next bound is unavailable"
else
  err "ledger-append.py must omit an unknowable swept bound (rc $rc): $out"
fi

EMPTY_RUN="$LEDGER_FIX/empty-run"
mkdir "$EMPTY_RUN"
out=$(python3 scripts/ledger-append.py --run "$EMPTY_RUN" --repo fixture \
  --ledger "$LEDGER_FIX/empty.jsonl" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -e "$LEDGER_FIX/empty.jsonl" ]; then
  ok "ledger-append.py accepts an empty sweep without output"
else
  err "ledger-append.py empty sweep expected rc 0 and no output (rc $rc): $out"
fi

out=$(python3 scripts/ledger-append.py --job "$LEDGER_FIX/job" --run "$EMPTY_RUN" \
  --skill fire --repo fixture --ledger "$LEDGER_FIX/caller.jsonl" 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'exactly one of --job or --run'; then
  ok "ledger-append.py rejects both input modes"
else
  err "ledger-append.py must reject both input modes (rc $rc): $out"
fi
out=$(python3 scripts/ledger-append.py --repo fixture --ledger "$LEDGER_FIX/caller.jsonl" 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'exactly one of --job or --run'; then
  ok "ledger-append.py rejects a missing input mode"
else
  err "ledger-append.py must require one input mode (rc $rc): $out"
fi
out=$(python3 scripts/ledger-append.py --run "$EMPTY_RUN" --lap 1 --branch feat/test \
  --repo fixture --ledger "$LEDGER_FIX/caller.jsonl" 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q -- '--lap and --branch are not valid with --run'; then
  ok "ledger-append.py rejects lap metadata in sweep mode"
else
  err "ledger-append.py must reject sweep lap metadata (rc $rc): $out"
fi
tab=$(bash scripts/tab.sh "$FIXHOME/missing-ledger.jsonl")
rc=$?
[ "$rc" -eq 0 ] && [ "$tab" = '{"jobs": 0}' ] && ok "tab.sh drops missing ledger" || err "tab.sh missing ledger expected rc 0 and '{\"jobs\": 0}', got rc $rc and '$tab'"

# A token count pasted with its thousands separator is invalid JSON. Found in a real
# ledger, where it took every other run's total down with it.
TAB_CORRUPT=$(mktemp)
printf '%s\n' \
  '{"ts":"2026-01-01T00:00:00Z","repo":"r","skill":"fire","model":"m","tokens":100,"claude_tokens":10}' \
  '{"ts":"2026-01-01T00:00:00Z","repo":"r","skill":"taste","model":"m","tokens":97,188}' \
  '{"ts":"2026-01-01T00:00:00Z","repo":"r","skill":"refire","model":"m","tokens":200,"claude_tokens":20}' \
  > "$TAB_CORRUPT"
tab=$(bash scripts/tab.sh "$TAB_CORRUPT" | tr -d ' \n')
rc=$?
if [ "$rc" -eq 0 ] &&
  printf '%s' "$tab" | grep -qF '"jobs":2' &&
  printf '%s' "$tab" | grep -qF '"worker_tokens":300' &&
  printf '%s' "$tab" | grep -qF '"unreadable_lines":1'; then
  ok "tab.sh survives a corrupt ledger line and counts it"
else
  err "tab.sh must skip an unparseable ledger line and report it (rc $rc): $tab"
fi
rm -f "$TAB_CORRUPT"

BENCH_LEDGER=$(mktemp)
BENCH_MUTATED=$(mktemp)
BENCH_MIXED=$(mktemp)
BENCH_INVALID=$(mktemp)
BENCH_RELATIVE_DIR=$(mktemp -d)
REPO_ROOT=$PWD
printf '%s\n' \
  '{"task":"t1","arm":"delegated","model":"gpt-5.6-terra","orchestrator":"claude-fable-5","worker_tokens":100000,"claude_tokens":10000,"verified":true,"wallclock_s":300}' \
  '{"task":"t1","arm":"direct","model":"claude-fable-5","orchestrator":"claude-fable-5","worker_tokens":0,"claude_tokens":80000,"verified":true,"wallclock_s":240}' \
  > "$BENCH_LEDGER"
bench=$(bash scripts/bench.sh "$BENCH_LEDGER")
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$bench" | grep -Fx '| t1 | delegated | gpt-5.6-terra | claude-fable-5 | 100,000 | 10,000 | ~$1.18 | yes | 300s |' >/dev/null \
  && printf '%s\n' "$bench" | grep -Fx '| t1 | direct | claude-fable-5 | claude-fable-5 | 0 | 80,000 | ~$2.40 | yes | 240s |' >/dev/null \
  && printf '%s\n' "$bench" | grep -Fx -- '- t1: direct − delegated = ~$1.22 (delegated lower; observed difference on this measured task set).' >/dev/null \
  && printf '%s\n' "$bench" | grep -Fx '**Aggregate:** 1 task compared; delegated total ~$1.18; direct total ~$2.40; total observed delta (direct − delegated) ~$1.22 (delegated lower; observed difference on this measured task set).' >/dev/null; then
  ok "bench.sh reports fixture rows and exact measured totals"
else
  err "bench.sh fixture totals are wrong (rc $rc): $bench"
fi
jq -c 'if .arm == "direct" then .verified = false else . end' "$BENCH_LEDGER" > "$BENCH_MUTATED"
bench=$(bash scripts/bench.sh "$BENCH_MUTATED")
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$bench" | grep -Fx '| t1 | direct | claude-fable-5 | claude-fable-5 | 0 | 80,000 | failed (excluded) | failed (excluded) | 240s |' >/dev/null \
  && printf '%s\n' "$bench" | grep -Fx '**Aggregate:** 0 tasks compared; delegated total ~$0.00; direct total ~$0.00; total observed delta (direct − delegated) n/a (no verified, priced task pairs).' >/dev/null \
  && ! printf '%s\n' "$bench" | grep -F '~$2.40' >/dev/null; then
  ok "bench.sh excludes failed arm after verified mutation"
else
  err "bench.sh failed-arm mutation exclusion is wrong (rc $rc): $bench"
fi
printf '%s\n' \
  '{"task":"t1","arm":"delegated","model":"gpt-5.6-terra","orchestrator":"claude-fable-5","worker_tokens":100000,"claude_tokens":10000,"verified":true,"wallclock_s":300}' \
  '{"task":"t1","arm":"direct","model":"claude-fable-5","orchestrator":"claude-fable-5","worker_tokens":0,"claude_tokens":80000,"verified":true,"wallclock_s":240}' \
  '{"task":"t2","arm":"delegated","model":"gpt-5.6-terra","orchestrator":"claude-fable-5","worker_tokens":100000,"claude_tokens":10000,"verified":true,"wallclock_s":300}' \
  '{"task":"t2","arm":"direct","model":"claude-fable-5","orchestrator":"claude-fable-5","worker_tokens":0,"claude_tokens":80000,"verified":false,"wallclock_s":240}' \
  '{"task":"t3","arm":"delegated","model":"gpt-5.6-terra","orchestrator":"claude-fable-5","worker_tokens":100000,"claude_tokens":10000,"verified":true,"wallclock_s":300}' \
  '{"task":"t4","arm":"delegated","model":"unpriced-model","orchestrator":"claude-fable-5","worker_tokens":100000,"claude_tokens":10000,"verified":true,"wallclock_s":300}' \
  '{"task":"t4","arm":"direct","model":"claude-fable-5","orchestrator":"claude-fable-5","worker_tokens":0,"claude_tokens":80000,"verified":true,"wallclock_s":240}' \
  > "$BENCH_MIXED"
bench=$(bash scripts/bench.sh "$BENCH_MIXED")
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$bench" | grep -Fx -- '- t2: no delta — direct arm failed verification.' >/dev/null \
  && printf '%s\n' "$bench" | grep -Fx -- '- t3: no delta — missing direct arm.' >/dev/null \
  && printf '%s\n' "$bench" | grep -Fx -- '- t4: no delta — delegated arm is unpriced.' >/dev/null \
  && printf '%s\n' "$bench" | grep -Fx '**Aggregate:** 1 task compared; delegated total ~$1.18; direct total ~$2.40; total observed delta (direct − delegated) ~$1.22 (delegated lower; observed difference on this measured task set).' >/dev/null; then
  ok "bench.sh reconciles totals on complete verified priced pairs only"
else
  err "bench.sh mixed-ledger reconciliation is wrong (rc $rc): $bench"
fi
# Orchestration is priced per row at the model that ran it. Pricing every arm at one
# reference orchestrator overstated a direct arm on a cheaper Claude - here it would
# report ~$2.40 instead of ~$1.20 and inflate the delta from ~$0.17 to ~$1.23, in
# delegation's favour.
printf '%s\n' \
  '{"task":"cheap-orch","arm":"delegated","model":"gpt-5.6-terra","orchestrator":"claude-opus-5","worker_tokens":100000,"claude_tokens":10000,"verified":true,"wallclock_s":300}' \
  '{"task":"cheap-orch","arm":"direct","model":"claude-opus-5","orchestrator":"claude-opus-5","worker_tokens":0,"claude_tokens":80000,"verified":true,"wallclock_s":240}' \
  > "$BENCH_MIXED"
bench=$(bash scripts/bench.sh "$BENCH_MIXED")
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$bench" | grep -Fx '**Aggregate:** 1 task compared; delegated total ~$1.03; direct total ~$1.20; total observed delta (direct − delegated) ~$0.17 (delegated lower; observed difference on this measured task set).' >/dev/null \
  && ! printf '%s\n' "$bench" | grep -F '~$2.40' >/dev/null; then
  ok "bench.sh prices each arm's orchestration at the model that ran it"
else
  err "bench.sh priced orchestration at a reference model instead of the row's own (rc $rc): $bench"
fi
printf '%s\n' '{"task":"invalid-direct","arm":"direct","model":"claude-fable-5","orchestrator":"claude-fable-5","worker_tokens":1,"claude_tokens":1,"verified":true,"wallclock_s":1}' > "$BENCH_INVALID"
bench=$(bash scripts/bench.sh "$BENCH_INVALID" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && [ "$bench" = 'bench: invalid JSONL schema, duplicate task/arm row, direct arm worker_tokens is not zero, or direct arm model differs from its orchestrator' ]; then
  ok "bench.sh rejects direct arms with worker tokens"
else
  err "bench.sh direct worker-token validation is wrong (rc $rc): $bench"
fi
# jq's % truncates its operands, so `. % 1 == 0` accepts 5.5 - a fractional token
# count would render verbatim in the table. Integer-ness is asserted, not assumed.
printf '%s\n' '{"task":"fractional","arm":"delegated","model":"gpt-5.6-terra","orchestrator":"claude-fable-5","worker_tokens":100000.7,"claude_tokens":10,"verified":true,"wallclock_s":1}' > "$BENCH_INVALID"
bench=$(bash scripts/bench.sh "$BENCH_INVALID" 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  ok "bench.sh rejects fractional token counts"
else
  err "bench.sh accepted a fractional token count (rc $rc): $bench"
fi
cp "$BENCH_LEDGER" "$BENCH_RELATIVE_DIR/local-bench.jsonl"
bench=$(cd "$BENCH_RELATIVE_DIR" && bash "$REPO_ROOT/scripts/bench.sh" local-bench.jsonl)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$bench" | grep -Fx '# expo benchmark report' >/dev/null; then
  ok "bench.sh resolves caller-relative ledgers"
else
  err "bench.sh caller-relative ledger resolution is wrong (rc $rc): $bench"
fi
rm -rf "$FIXHOME" "$TAB_LEDGER" "$LEDGER_FIX" "$BENCH_LEDGER" "$BENCH_MUTATED" "$BENCH_MIXED" "$BENCH_INVALID" "$BENCH_RELATIVE_DIR"
section_ok "measurement scripts"

# 4. Link sweep ---------------------------------------------------------------
# Every receipt cites a URL; dead links rot the receipts. Hard 404/410 fails.
if [ "${SKIP_LINKS:-}" != 1 ]; then
  for u in $(grep -rhoE 'https?://[^) >"`]+' README.md docs/design.md skills/receipts/references/prices.md | sed 's/[.,;]$//' | sort -u); do
    code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 10 \
      -A 'Mozilla/5.0 (expo link check)' "$u" 2>/dev/null)
    case $code in
      2*|3*) ;;
      404|410) err "dead link ($code): $u" ;;
      *) warn "link returned $code (not failing - transient or bot-blocked): $u" ;;
    esac
  done
  section_ok "link sweep"
fi

if [ "$fail" -eq 0 ]; then echo "all checks passed"; else echo "$fail check(s) FAILED"; fi
exit $((fail > 0))
