#!/usr/bin/env python3
"""Warning contracts exercised through the CLI; all writes stay in a temp dir."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "scripts/fixtures"
UNMEASURED = "ledger-append: no --session given - orchestration tokens not measured"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def nonempty(path):
    text = path.read_text(encoding="utf-8")
    require(text.strip(), f"fixture missing or empty: {path}")
    return text


def seed(base, name, model, stamped=True):
    job = base / name
    job.mkdir(parents=True)
    log, count = re.subn(r"^model: .+$", f"model: {model}",
                         nonempty(FIXTURES / "ledger-complete.log"), flags=re.M)
    require(count == 1, "fixture must have exactly one banner model")
    (job / "job.log").write_text(log, encoding="utf-8")
    (job / "result.md").write_text(nonempty(FIXTURES / "ledger-complete.result"), encoding="utf-8")
    (job / "findings.md").write_text(nonempty(FIXTURES / "ledger-findings-clean.findings"), encoding="utf-8")
    if stamped:
        (job / "git-common-dir").write_text("/fixture/.git\n", encoding="utf-8")
    return job


def run(base, script, jobs, skill="taste", sweep=False):
    ledger = base / "ledger.jsonl"
    command = [sys.executable, str(script), "--repo", "fixture", "--ledger", str(ledger)]
    command += ["--run", str(base / "run")] if sweep else ["--job", str(jobs[0]), "--skill", skill]
    if skill == "simmer":
        command += ["--lap", "1", "--branch", "fixture"]
    env = dict(os.environ, HOME=str(base / "home"), EXPO_CLAUDE_HOME=str(base / "claude"))
    result = subprocess.run(command, capture_output=True, text=True, env=env)
    require(result.returncode == 0, f"CLI failed ({result.returncode}): {result.stderr}")
    rows = [json.loads(line) for line in ledger.read_text(encoding="utf-8").splitlines()]
    require(len(rows) == len(jobs) > 0, "every fixture job must still write exactly one row")
    require([json.loads(line) for line in result.stdout.splitlines()] == rows,
            "stdout must match the appended rows")
    # A sweep orders unstamped jobs by scandir order, which is not creation order.
    markers = [json.loads((job / ".ledgered").read_text()) for job in jobs]
    require(sorted(map(json.dumps, markers)) == sorted(map(json.dumps, rows)),
            "markers must preserve every appended row")
    for row, job in zip(markers, jobs):
        expected = json.loads(nonempty(FIXTURES / "ledger-complete.expected"))
        expected.update(ts=row["ts"], skill=skill,
                        model=re.search(r"^model: (.+)$", (job / "job.log").read_text(), re.M)[1])
        if skill == "taste":
            expected.update(verdict="ship", confirmed=0, refuted=1, diff_lines=37, **{"pass": "first"})
        elif skill == "fire":
            expected.update(tier="sol", shape="standard", override=False)
        elif skill == "simmer":
            expected.update(lap=1, branch="fixture")
        require(row == expected, f"warning changed row contents: {row}")
    require(not (base / "home/.expo").exists(), "fixture wrote to HOME instead of --ledger")
    return result.stderr.splitlines()


def plugin_copy(base):
    script = base / "plugin/scripts/ledger-append.py"
    script.parent.mkdir(parents=True)
    shutil.copyfile(ROOT / "scripts/ledger-append.py", script)
    return script


def check(case, base):
    script = ROOT / "scripts/ledger-append.py"
    # Parse the documented invocation independently of the appender's pin reader.
    pins = [line.split()[1].removeprefix("model=")
            for line in nonempty(ROOT / "skills/taste/SKILL.md").splitlines()
            if line.lstrip().startswith("-c model=")]
    require(len(pins) == 1 and pins[0], "reviewer pin fixture unavailable or ambiguous")
    pin = pins[0]
    stale = "fixture-stale-reviewer"
    require(stale != pin, "stale model must differ from the pin")
    if case == "pin":
        for label, model in (("stale", stale), ("pinned", pin)):
            scenario = base / label
            job = seed(scenario, "taste-job", model)
            expected = [] if model == pin else [
                f"ledger-append: taste model {model} differs from the pinned reviewer {pin} - stale stage instructions?"]
            actual = run(scenario, script, [job])
            require(actual == expected + [UNMEASURED], f"{label} pin warning: {actual}")
        # A different sibling pin must be read, while an inline prose pin is ignored.
        scenario = base / "changed-pin"
        copied = plugin_copy(scenario)
        taste = scenario / "plugin/skills/taste/SKILL.md"
        taste.parent.mkdir(parents=True)
        taste.write_text("prose -c model=decoy\n  -c model=fixture-current-reviewer \\\n", encoding="utf-8")
        job = seed(scenario, "taste-job", "fixture-current-reviewer")
        require(run(scenario, copied, [job]) == [UNMEASURED], "sibling pin was not read dynamically")
        job = seed(base / "non-taste", "refire-job", stale)
        require(run(base / "non-taste", script, [job], skill="refire") == [UNMEASURED],
                "pin comparison must apply only to taste")
    elif case == "stamp":
        for skill in ("fire", "taste", "refire", "simmer"):
            for stamped in (False, True):
                scenario = base / f"{skill}-{stamped}"
                job = seed(scenario, "job", pin, stamped)
                if skill == "fire":
                    (job / "tier").write_text("tier: sol shape=standard override=no\n")
                expected = [] if stamped else ["ledger-append: repo stamp missing"]
                actual = run(scenario, script, [job], skill=skill)
                require(actual == expected + [UNMEASURED], f"{skill} stamp warning: {actual}")
    elif case == "unreadable":
        for broken in ("missing", "directory", "no-pin"):
            scenario = base / broken
            copied = plugin_copy(scenario)
            taste = scenario / "plugin/skills/taste/SKILL.md"
            taste.parent.mkdir(parents=True)
            if broken == "directory":
                taste.mkdir()
            elif broken == "no-pin":
                taste.write_text("prose -c model=decoy\n", encoding="utf-8")
            jobs = [seed(scenario / "run", f"taste-{index}", stale) for index in range(2)]
            actual = run(scenario, copied, jobs, sweep=True)
            warnings = [line for line in actual if line.startswith("ledger-append: reviewer pin unreadable: ")]
            require(len(warnings) == 1 and len(warnings[0].split(": ", 2)[-1]) > 0,
                    f"{broken} pin must warn once per invocation: {actual}")
            require(sorted(actual) == sorted(warnings + [UNMEASURED] * 2),
                    f"{broken} pin must skip comparison and preserve other warnings: {actual}")
            print(warnings[0])
    else:
        raise ValueError(f"unknown warning scenario: {case}")


try:
    with tempfile.TemporaryDirectory(prefix="expo-ledger-warnings-") as directory:
        check(sys.argv[1], Path(directory))
    print(f"ok ledger {sys.argv[1]} warning contract")
except Exception as error:
    print(f"{type(error).__name__}: {error}", file=sys.stderr)
    sys.exit(1)
