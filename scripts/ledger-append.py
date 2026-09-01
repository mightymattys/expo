#!/usr/bin/env python3
"""Append measured Codex jobs to expo's running ledger, or nothing."""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone


MODEL_RE = re.compile(r"^\s*model:\s*(\S.*?)\s*$")
WORKDIR_RE = re.compile(r"^\s*workdir:\s*(\S.*?)\s*$")
TOKENS_RE = re.compile(r"^\s*(\d+|\d{1,3}(?:,\d{3})+)\s*$")
INTEGER_RE = re.compile(r"^\d+$")
SKILLS = ("fire", "taste", "refire", "simmer")
APPENDED = "appended"
PER_DIR_ERROR = "per-dir-error"
SKIPPED = "skipped"
FATAL = "fatal"


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
    workdir = None
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
        match = WORKDIR_RE.match(line)
        if match:
            workdir = match.group(1)
    if not model:
        return None

    # A completed run always writes --output-last-message. Without it the log's tail is
    # just wherever the worker stopped - and a log echoes its whole ticket, so "ends with
    # a token summary" is text an interrupted or compromised run can supply. Verified: a
    # log with a valid banner and no result.md, ending in an echoed `tokens used\n999,999`,
    # used to produce a 999,999-token row. No result.md means no row.
    result = os.path.join(job, "result.md")
    if not os.path.exists(result):
        return None
    with open(result, encoding="utf-8") as source:
        final_message = source.read().rstrip()
    # Codex writes the final message verbatim to result.md; remove that suffix before
    # reading the closing summary, so arbitrary final text cannot supply it. The log
    # carries a trailing newline the result file does not, so both ends are rstripped
    # before the suffix is matched.
    trimmed = text.rstrip()
    if not final_message or not trimmed.endswith(final_message):
        return None
    lines = trimmed[:-len(final_message)].splitlines(keepends=True)

    while lines and not lines[-1].strip():
        lines.pop()
    if len(lines) < 2 or lines[-2].strip() != "tokens used":
        return None
    match = TOKENS_RE.match(lines[-1])
    if not match:
        return None
    value = match.group(1).replace(",", "")
    return model, int(value), workdir


def started_stamp(job):
    try:
        with open(os.path.join(job, "started"), encoding="utf-8") as source:
            started = source.read().strip()
    except Exception:
        return None, None, "no started stamp in the job dir - orchestration tokens not measured"
    if not started:
        return None, None, "empty started stamp - orchestration tokens not measured"
    try:
        parsed = datetime.fromisoformat(started.replace("Z", "+00:00"))
    except Exception:
        return None, None, "unparseable started stamp in the job dir - orchestration tokens not measured"
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return started, parsed.astimezone(timezone.utc), None


def claude_tokens(job, session, until=None, window_error=None):
    # Returns (tokens, None) or (None, reason). The reason is reported on stderr: an
    # omitted field is honest, but a SILENTLY omitted one leaves nobody able to say
    # which precondition failed - and 42% of a real ledger's lines lost the field with
    # no way left to find out why.
    if not session:
        return None, "no --session given - orchestration tokens not measured"
    started, _, started_error = started_stamp(job)
    if started_error:
        return None, started_error
    if window_error:
        return None, window_error
    try:
        command = [
            sys.executable, os.path.join(os.path.dirname(__file__), "orch-tokens.py"),
            session, started,
        ]
        if until is not None:
            command.append(until)
        output = subprocess.run(
            command,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        ).stdout.strip()
    except Exception:
        return None, "orch-tokens.py could not run - orchestration tokens not measured"
    if INTEGER_RE.fullmatch(output):
        return int(output), None
    return None, f"orch-tokens.py measured nothing since {started} - orchestration tokens not measured"


def append_job(job, skill, lap, branch, session, repo_value, ledger, until=None,
               window_error=None):
    log = os.path.join(job, "job.log")
    if not os.path.isdir(job):
        print(f"ledger-append: job directory not found: {job}", file=sys.stderr)
        return PER_DIR_ERROR
    if not os.path.isfile(log):
        print(f"ledger-append: job log not found: {log}", file=sys.stderr)
        return PER_DIR_ERROR

    try:
        measured = measured_job(job)
    except Exception as error:
        print(f"ledger-append: cannot read job log: {error}", file=sys.stderr)
        return PER_DIR_ERROR
    if measured is None:
        return SKIPPED
    model, tokens, workdir = measured
    repo = repo_value or (os.path.basename(os.path.normpath(workdir)) if workdir else None)
    if not repo:
        print(f"ledger-append: job log has no workdir: {log} - cannot resolve repo name",
              file=sys.stderr)
        return SKIPPED
    line = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo": repo,
        "skill": skill,
        "model": model,
        "tokens": tokens,
    }
    orchestration, unmeasured = claude_tokens(job, session, until, window_error)
    if orchestration is not None:
        line["claude_tokens"] = orchestration
    if skill == "simmer":
        if lap is not None:
            line["lap"] = lap
        if branch is not None:
            line["branch"] = branch

    try:
        parent = os.path.dirname(os.path.abspath(ledger))
        os.makedirs(parent, exist_ok=True)
        encoded = json.dumps(line, separators=(",", ":"))
        with open(ledger, "a", encoding="utf-8") as target:
            target.write(encoded + "\n")
    except Exception:
        print(f"ledger-append: cannot write ledger: {ledger}", file=sys.stderr)
        return FATAL

    marker = os.path.join(job, ".ledgered")
    # The ledger append is already durable here. If this marker write fails, a retry
    # can duplicate the row; closing that window requires an out-of-scope schema change.
    try:
        with open(marker, "w", encoding="utf-8") as target:
            target.write(encoded + "\n")
    except Exception:
        print(encoded)
        print(f"ledger-append: cannot write marker: {marker}", file=sys.stderr)
        return FATAL
    if unmeasured:
        print(f"ledger-append: {unmeasured}", file=sys.stderr)
    print(encoded)
    return APPENDED


def sweep_entries(directory):
    entries = []
    for index, entry in enumerate(os.scandir(directory)):
        if not entry.is_dir():
            continue
        started, order, started_error = started_stamp(entry.path)
        entries.append((entry.name, entry.path, started, order, started_error, index))
    return entries


def sweep_jobs(entries, session, repo_value, ledger, window_error=None,
               known_bounds_only=False):
    skipped = 0
    jobs = []
    for entry in entries:
        name, job = entry[:2]
        skill = name.split("-", 1)[0]
        if skill not in SKILLS:
            print(f"ledger-append: skipped unrecognised job dir: {job}", file=sys.stderr)
            skipped += 1
            continue
        if skill == "simmer":
            print(f"ledger-append: skipped simmer job dir: {job} - laps are ledgered per lap with --lap and --branch",
                  file=sys.stderr)
            skipped += 1
            continue
        jobs.append(entry)

    jobs.sort(key=lambda item: (
        item[3] is None, item[3] or datetime.max.replace(tzinfo=timezone.utc), item[5],
    ))
    for index, (name, job, _, _, _, _) in enumerate(jobs):
        skill = name.split("-", 1)[0]
        marker = os.path.join(job, ".ledgered")
        # Presence is authoritative even when the marker is empty or unreadable: it
        # may follow a successful append, so retrying would risk a duplicate line.
        if os.path.lexists(marker):
            print(f"ledger-append: skipped already ledgered job dir: {job}",
                  file=sys.stderr)
            skipped += 1
            continue
        until = None
        job_window_error = window_error
        if job_window_error is None and index + 1 < len(jobs):
            if known_bounds_only:
                # Unknown-start jobs contribute no orchestration at all, so bounding
                # at the next known start is safe even when one ran in between.
                next_started = jobs[index + 1][2]
                if next_started is not None:
                    until = next_started
            else:
                next_started = jobs[index + 1][2]
                next_error = jobs[index + 1][4]
                if next_error:
                    job_window_error = next_error.replace("the job dir", "the next job dir")
                else:
                    until = next_started
        result = append_job(
            job, skill, None, None, session, repo_value, ledger, until, job_window_error,
        )
        if result == FATAL:
            return skipped, FATAL
        if result == SKIPPED:
            print(f"ledger-append: skipped unmeasurable job dir: {job}", file=sys.stderr)
            skipped += 1
        elif result == PER_DIR_ERROR:
            skipped += 1
    return skipped, None


def main():
    parser = SilentParser(add_help=False)
    parser.add_argument("--job")
    parser.add_argument("--run")
    parser.add_argument("--skill", choices=SKILLS)
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

    if (args.job is None) == (args.run is None):
        print("ledger-append: exactly one of --job or --run is required", file=sys.stderr)
        return 1

    if args.run is not None:
        if args.lap is not None or args.branch is not None:
            print("ledger-append: --lap and --branch are not valid with --run", file=sys.stderr)
            return 1
        if args.skill is not None:
            print("ledger-append: --skill is only valid with --job", file=sys.stderr)
            return 1
    elif args.skill is None:
        print("ledger-append: --job requires --skill", file=sys.stderr)
        return 1
    elif args.skill == "simmer":
        if args.lap is None or args.lap <= 0:
            print("ledger-append: --skill simmer requires a positive --lap", file=sys.stderr)
            return 1
        if not args.branch or not args.branch.strip():
            print("ledger-append: --skill simmer requires a non-empty --branch", file=sys.stderr)
            return 1
    elif args.lap is not None or args.branch is not None:
        print("ledger-append: --lap and --branch are only valid with --skill simmer", file=sys.stderr)
        return 1

    ledger = args.ledger or os.path.expanduser("~/.expo/ledger.jsonl")

    if args.job is not None:
        marker = os.path.join(args.job, ".ledgered")
        if os.path.lexists(marker):
            print(f"ledger-append: skipped already ledgered job dir: {args.job}",
                  file=sys.stderr)
            return 0
        result = append_job(
            args.job, args.skill, args.lap, args.branch, args.session, args.repo, ledger,
        )
        return 1 if result in (PER_DIR_ERROR, FATAL) else 0

    if not os.path.isdir(args.run):
        print(f"ledger-append: run directory not found: {args.run}", file=sys.stderr)
        return 1
    try:
        entries = sweep_entries(args.run)
    except Exception as error:
        print(f"ledger-append: cannot read run directory: {args.run}: {error}",
              file=sys.stderr)
        return 1

    if os.path.basename(os.path.normpath(args.run)).startswith("serve-"):
        skipped, fatal = sweep_jobs(entries, args.session, args.repo, ledger)
        if fatal:
            return 1
    else:
        scratchpad_entries = [entry for entry in entries if not entry[0].startswith("serve-")]
        scratchpad_skipped = 0
        for name, path, _, _, _, _ in entries:
            if not name.startswith("serve-"):
                continue
            try:
                nested_entries = sweep_entries(path)
            except Exception as error:
                print(f"ledger-append: cannot read run directory: {path}: {error}",
                      file=sys.stderr)
                scratchpad_skipped += 1
                continue
            scratchpad_entries.extend(nested_entries)
        # Give ties a single, deterministic sweep-local order after flattening both
        # direct and nested jobs into the session's one transcript timeline.
        scratchpad_entries = [entry[:5] + (index,)
                              for index, entry in enumerate(scratchpad_entries)]
        skipped, fatal = sweep_jobs(
            scratchpad_entries, args.session, args.repo, ledger, known_bounds_only=True,
        )
        skipped += scratchpad_skipped
        if fatal:
            return 1
    if skipped:
        print(f"ledger-append: sweep skipped {skipped} job dir(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
