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
must_contain skills/simmer/SKILL.md 'started:'  "the receipt template reads loop.md's started: for wallclock"
must_contain skills/serve/SKILL.md  'findings:' "refire (via serve) reads state.md's findings: line"
must_contain skills/serve/SKILL.md  'baseline:' "taste's post-fire scope reads state.md's baseline: line"
must_contain skills/taste/SKILL.md  'tree:'     "refire's preflight reads findings.md's tree: anchor"
must_contain skills/serve/SKILL.md  'tier:'     "refire reads state.md's tier: line for the worker tier"
must_contain skills/refire/SKILL.md 'tier:'     "refire must read the tier serve recorded"
must_contain skills/simmer/SKILL.md 'tier:'     "every lap's invocation reads loop.md's tier: line"

# A receipt's only savings claim is explicitly qualified with a floor or bound.
while IFS= read -r line; do
  lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
  case $lower in
    *floor*|*'>='*|*'≥'*) ;;
    *) err "unqualified savings claim: $line" ;;
  esac
done < <(grep -rinE -- 'sav(e|ed|ings?)\b' skills/receipts/ || true)

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

# One ledger line schema, defined once (fire); each writer names its own skill tag.
n=$(grep -rlF '{"ts":' skills/ | wc -l | tr -d ' ')
[ "$n" = 1 ] || err "ledger line schema must be defined in exactly one file (found $n)"
for s in taste refire simmer; do
  must_contain "skills/$s/SKILL.md" "\"skill\":\"$s\"" "its ledger lines carry its own skill tag"
done

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
