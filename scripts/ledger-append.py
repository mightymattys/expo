#!/usr/bin/env python3
"""Append one measured Codex job to expo's running ledger, or nothing."""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone


MODEL_RE = re.compile(r"^\s*model:\s*(\S.*?)\s*$")
TOKENS_RE = re.compile(r"^\s*(\d+|\d{1,3}(?:,\d{3})+)\s*$")
INTEGER_RE = re.compile(r"^\d+$")


class SilentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def measured_job(job):
    with open(os.path.join(job, "job.log"), encoding="utf-8") as source:
        text = source.read()
    lines = text.splitlines(keepends=True)

    banner_start = None
    for index, line in enumerate(lines):
        if line.strip() == "--------":
            banner_start = index
            break
    if banner_start is None:
        return None

    model = None
    banner_end = None
    for index in range(banner_start + 1, len(lines)):
        if lines[index].strip() == "--------":
            banner_end = index
            break
    if banner_end is None:
        return None
    for line in lines[banner_start + 1:banner_end]:
        match = MODEL_RE.match(line)
        if match:
            model = match.group(1)
            break
    if not model:
        return None

    result = os.path.join(job, "result.md")
    if os.path.exists(result):
        with open(result, encoding="utf-8") as source:
            final_message = source.read().rstrip()
        # Codex writes the final message verbatim to result.md; remove that suffix
        # before reading the closing summary, so arbitrary final text cannot supply it.
        # The log carries a trailing newline the result file does not, so both ends are
        # rstripped before the suffix is matched.
        trimmed = text.rstrip()
        if not final_message or not trimmed.endswith(final_message):
            return None
        lines = trimmed[:-len(final_message)].splitlines(keepends=True)

    # Without result.md, only EOF is trusted: an interrupted job has no final message.
    while lines and not lines[-1].strip():
        lines.pop()
    if len(lines) < 2 or lines[-2].strip() != "tokens used":
        return None
    match = TOKENS_RE.match(lines[-1])
    if not match:
        return None
    value = match.group(1).replace(",", "")
    return model, int(value)


def repo_name(value):
    if value:
        return value
    try:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True,
        ).stdout.strip()
    except Exception:
        return None
    return os.path.basename(root) or None


def claude_tokens(job, session):
    if not session:
        return None
    try:
        with open(os.path.join(job, "started"), encoding="utf-8") as source:
            started = source.read().strip()
    except Exception:
        return None
    if not started:
        return None
    try:
        output = subprocess.run(
            [sys.executable, os.path.join(os.path.dirname(__file__), "orch-tokens.py"),
             session, started],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        ).stdout.strip()
    except Exception:
        return None
    return int(output) if INTEGER_RE.fullmatch(output) else None


def main():
    parser = SilentParser(add_help=False)
    parser.add_argument("--job", required=True)
    parser.add_argument("--skill", required=True,
                        choices=("fire", "taste", "refire", "simmer"))
    parser.add_argument("--lap", type=int)
    parser.add_argument("--branch")
    parser.add_argument("--session")
    parser.add_argument("--repo")
    parser.add_argument("--ledger")
    try:
        args = parser.parse_args()
    except (SystemExit, ValueError) as error:
        print(f"ledger-append: {error}", file=sys.stderr)
        return 1

    if args.skill == "simmer":
        if args.lap is None or args.lap <= 0:
            print("ledger-append: --skill simmer requires a positive --lap", file=sys.stderr)
            return 1
        if not args.branch or not args.branch.strip():
            print("ledger-append: --skill simmer requires a non-empty --branch", file=sys.stderr)
            return 1
    elif args.lap is not None or args.branch is not None:
        print("ledger-append: --lap and --branch are only valid with --skill simmer", file=sys.stderr)
        return 1

    log = os.path.join(args.job, "job.log")
    if not os.path.isdir(args.job):
        print(f"ledger-append: job directory not found: {args.job}", file=sys.stderr)
        return 1
    if not os.path.isfile(log):
        print(f"ledger-append: job log not found: {log}", file=sys.stderr)
        return 1

    try:
        measured = measured_job(args.job)
    except Exception as error:
        print(f"ledger-append: cannot read job log: {error}", file=sys.stderr)
        return 1
    repo = repo_name(args.repo)
    if repo is None:
        print("ledger-append: cannot resolve repo name", file=sys.stderr)
        return 1
    if measured is None:
        return 0
    model, tokens = measured
    line = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo": repo,
        "skill": args.skill,
        "model": model,
        "tokens": tokens,
    }
    orchestration = claude_tokens(args.job, args.session)
    if orchestration is not None:
        line["claude_tokens"] = orchestration
    if args.skill == "simmer":
        if args.lap is not None:
            line["lap"] = args.lap
        if args.branch is not None:
            line["branch"] = args.branch

    ledger = args.ledger or os.path.expanduser("~/.expo/ledger.jsonl")
    try:
        parent = os.path.dirname(os.path.abspath(ledger))
        os.makedirs(parent, exist_ok=True)
        encoded = json.dumps(line, separators=(",", ":"))
        with open(ledger, "a", encoding="utf-8") as target:
            target.write(encoded + "\n")
    except Exception:
        print(f"ledger-append: cannot write ledger: {ledger}", file=sys.stderr)
        return 1
    print(encoded)
    return 0


if __name__ == "__main__":
    sys.exit(main())
