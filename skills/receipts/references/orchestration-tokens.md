# Measuring orchestration tokens from the session transcript

The worker's tokens are measured (job.log). The head chef's own tokens - the ticket,
the diff review, the report - used to be an estimate ("~5-7k per run"). They are
measurable too: Claude Code writes the live session to a JSONL transcript, one line
per message, each assistant line carrying a `usage` block. Summing uncached input +
output since the run's `started:` timestamp gives the run's real orchestration cost -
the same "uncached input + output" basis the worker tokens use, so the two are
comparable.

The live session's transcript is named for its session id, which Claude Code exports
as `$CLAUDE_CODE_SESSION_ID` - so the file is located exactly, with no cwd-slug
guessing and no newest-mtime heuristic that a concurrent session could poison. Run
this at plating (substitute `<started>` with state.md's `started:` ISO timestamp):

```bash
python3 - "$CLAUDE_CODE_SESSION_ID" "<started>" <<'PY'
import json, sys, glob, os
sid, started = sys.argv[1], sys.argv[2]
matches = glob.glob(os.path.expanduser(f'~/.claude/projects/*/{sid}.jsonl'))
if not matches:
    print(''); sys.exit(0)          # no transcript found - drop the line, never guess
inp = out = 0
for line in open(matches[0]):
    try: d = json.loads(line)
    except Exception: continue
    if d.get('type') != 'assistant': continue
    if d.get('timestamp', '') < started: continue
    u = d.get('message', {}).get('usage', {})
    inp += u.get('input_tokens', 0); out += u.get('output_tokens', 0)
print(inp + out)                    # orchestration tokens, uncached input + output
PY
```

If `$CLAUDE_CODE_SESSION_ID` is unset (an older Claude Code, or a non-interactive
context that doesn't export it), print nothing and drop the orchestration line -
don't fall back to a slug or mtime guess.

Honesty rules, same as everywhere else:

- **Empty output = drop the line.** No transcript, no session match, no assistant
  messages in the window → the receipt omits the orchestration line rather than
  guessing. Never fall back to the old 5-7k estimate.
- **It measures token volume, not a cost multiple.** Worker tokens and orchestrator
  tokens are different models with different tokenizers and $/token, so the honest
  derived figure is the API-list **dollar** split (worker tokens × worker blend vs
  orchestration tokens × Fable blend, both from prices.md), not a raw token ratio
  dressed up as savings.
- **It bounds to this run** via `started:`. A resumed or compacted session still
  works: the transcript is append-only and the timestamp filter keeps earlier work
  out. If the session was compacted mid-run the count is a floor, not exact - say so
  if it matters.
