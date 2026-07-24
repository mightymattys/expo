#!/usr/bin/env python3
# Prints nothing when a measurement cannot be made.
# Callers treat no output as "drop the line".
# It never guesses a transcript or token count.
import glob, json, os, sys
from datetime import datetime

def stamp(value):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except Exception:
        return None

if len(sys.argv) not in (3, 4):
    sys.exit(0)
session_id, since = sys.argv[1:3]
start = stamp(since)
end = stamp(sys.argv[3]) if len(sys.argv) == 4 else None
if start is None or (len(sys.argv) == 4 and end is None):
    sys.exit(0)
claude_home = os.environ.get("EXPO_CLAUDE_HOME", os.path.expanduser("~/.claude"))
matches = glob.glob(os.path.join(claude_home, "projects", "*", f"{session_id}.jsonl"))
if len(matches) != 1:
    sys.exit(0)
total = hits = 0
try:
    with open(matches[0], encoding="utf-8") as transcript:
        for line in transcript:
            try:
                data = json.loads(line)
            except Exception:
                continue
            if not isinstance(data, dict) or data.get("type") != "assistant":
                continue
            at = stamp(data.get("timestamp", ""))
            if at is None or at < start or (end is not None and at >= end):
                continue
            message = data.get("message")
            usage = message.get("usage") if isinstance(message, dict) else None
            if not isinstance(usage, dict):
                sys.exit(0)
            input_tokens = usage.get("input_tokens", 0)
            output_tokens = usage.get("output_tokens", 0)
            if type(input_tokens) is not int or type(output_tokens) is not int:
                sys.exit(0)
            total += input_tokens + output_tokens
            hits += 1
except Exception:
    sys.exit(0)
if hits:
    print(total)
