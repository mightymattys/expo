# Measuring orchestration tokens from the session transcript

The worker's tokens are measured (job.log). The head chef's own tokens - the ticket,
the diff review, the report - are measurable too: Claude Code writes the live session
to a JSONL transcript, one line per message, each assistant line carrying a `usage`
block. Summing uncached input + output over a bounded window gives real orchestration
cost - the same "uncached input + output" basis the worker tokens use, so the two are
comparable.

## Two windows, two purposes - never mix them

- **Ledger lines** (fire/taste/refire/simmer laps) measure **per job**: the window is
  `$JOB/started` → now. Every job dir writes its start at mint -
  `date -u +%Y-%m-%dT%H:%M:%SZ > "$JOB/started"` - so successive jobs in one serve
  have sequential, non-overlapping windows and the running tab can sum ledger lines
  without double-counting.
- **The run receipt** (serve/simmer, written once at the end) measures **per run**:
  the window is state.md's / loop.md's `started:` → now. One number for the whole
  run; it is NOT the sum of the ledger lines (the gaps between jobs belong to the
  run, not to any job).

## The measurement

The live session's transcript is named for its session id, which Claude Code exports
as `$CLAUDE_CODE_SESSION_ID` - so the file is located exactly, with no cwd-slug
guessing and no newest-mtime heuristic that a concurrent session could poison.
Substitute `<since>` with the window's start timestamp (per-job `$JOB/started` for a
ledger line; the run's `started:` for a receipt):

```bash
python3 - "$CLAUDE_CODE_SESSION_ID" "<since>" <<'PY'
import json, sys, glob, os
from datetime import datetime
sid, since = sys.argv[1], sys.argv[2]
def ts(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00'))
    except Exception: return None
start = ts(since)
matches = glob.glob(os.path.expanduser(f'~/.claude/projects/*/{sid}.jsonl'))
if not matches or start is None:
    sys.exit(0)                     # no transcript / bad anchor - print nothing
total, hits = 0, 0
for line in open(matches[0]):
    try: d = json.loads(line)
    except Exception: continue
    if d.get('type') != 'assistant': continue
    t = ts(d.get('timestamp', ''))
    if t is None or t < start: continue
    u = d.get('message', {}).get('usage', {})
    total += u.get('input_tokens', 0) + u.get('output_tokens', 0)
    hits += 1
if hits:
    print(total)                    # orchestration tokens, uncached input + output
PY
```

Timestamps are parsed as datetimes (not compared lexically), so fractional-second
transcript stamps compare correctly against a whole-second anchor. **No output means
drop the line** - that covers all of: `$CLAUDE_CODE_SESSION_ID` unset, no transcript
found, unparseable anchor, and zero assistant messages in the window. Never print a
guessed number and never fall back to a cwd-slug or newest-mtime file.

Honesty rules, same as everywhere else:

- **It measures token volume, not a cost multiple.** Worker tokens and orchestrator
  tokens are different models with different tokenizers and $/token, so the honest
  derived figure is the API-list **dollar** split (worker tokens × worker blend vs
  orchestration tokens × Fable blend, both from prices.md), not a raw token ratio
  dressed up as savings (the only permitted derived figure is the equal-volume delta, floor,
  per receipt-template.md).
- **A compacted session still works**: the transcript is append-only and the
  timestamp filter keeps earlier work out. If the session was compacted mid-window
  the count is a floor, not exact - say so if it matters.
