#!/usr/bin/env python3
"""Print counted change facts from a unified diff for review routing.

This stays separate from git so a caller can scan a saved delta without reading the
repository or changing it.
"""
import os
import re
import sys


# First matching kind wins. These path rules are intentionally the whole taxonomy.
FILE_KIND_RULES = {
    "tests": {
        "path_segments": ("test", "tests", "spec", "__tests__"),
        "basename_contains": ("test", "spec"),
    },
    "config": {
        "basenames": (
            "package.json", "tsconfig.json", "pyproject.toml", "Cargo.toml",
            "go.mod", "Makefile", "Dockerfile",
        ),
        "basename_prefixes": (".eslintrc",),
        "basename_suffixes": (".yml", ".yaml", ".toml", ".ini"),
    },
    "docs": {"basename_suffixes": (".md", ".rst", ".txt")},
    "generated": {
        "basename_suffixes": (".lock", "-lock.json"),
        "path_contains": ("node_modules", "vendor", "dist", "build"),
    },
    "source": {},
}

MANIFEST_BASENAMES = (
    "package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile",
    "requirements.txt",
)
GUARD_PATTERNS = (
    "catch", "except", "finally", "rescue", "throw", "raise", "assert",
    "validate", "if err != nil", "panic", "authoriz", "authent", "permission",
    "sanitize", "escape",
)
TEST_DECLARATION_PATTERNS = (
    "def test_", "it(", "test(", "describe(", "func Test", "#[test]", "@Test",
)
DEPENDENCY_ENTRY_PATTERNS = (
    r"^\s*[\"'][^\"']+[\"']\s*[:=]\s*[\"']?[<>=~^v*0-9]",
    r"^\s*[A-Za-z0-9_.@/+-]+\s*(?:==|>=|<=|~=|!=|=|>|<)\s*[v0-9]",
    r"^\s*[A-Za-z0-9_.@/+-]+\s+[v0-9][A-Za-z0-9_.+<>=~^*-]*",
    r"^\s*gem\s+[\"'][^\"']+[\"']\s*,\s*[\"']?[<>=~^v0-9]",
)
DEPENDENCY_ENTRY_RE = re.compile("|".join(DEPENDENCY_ENTRY_PATTERNS))


def unquote_git_path(value):
    """Decode one of Git's double-quoted, C-style path operands."""
    if not value.startswith('"'):
        return value, ""
    data = bytearray()
    index = 1
    escapes = {
        "a": b"\a", "b": b"\b", "f": b"\f", "n": b"\n", "r": b"\r",
        "t": b"\t", "v": b"\v", "\\": b"\\", '"': b'"',
    }
    while index < len(value):
        char = value[index]
        if char == '"':
            try:
                return data.decode("utf-8", "surrogateescape"), value[index + 1:]
            except UnicodeError:
                return None, value[index + 1:]
        if char != "\\":
            data.extend(char.encode("utf-8", "surrogateescape"))
            index += 1
            continue
        index += 1
        if index >= len(value):
            return None, ""
        char = value[index]
        if char in "01234567":
            digits = value[index:index + 3]
            if len(digits) != 3 or any(digit not in "01234567" for digit in digits):
                return None, ""
            data.append(int(digits, 8))
            index += 3
            continue
        escaped = escapes.get(char)
        if escaped is None:
            return None, ""
        data.extend(escaped)
        index += 1
    return None, ""


def path_from_header(value, prefix):
    """Return (valid, displayed path) from a --- or +++ header."""
    if value.startswith('"'):
        value, trailing = unquote_git_path(value)
        if value is None or (trailing and not trailing.startswith("\t")):
            return False, None
    else:
        value = value.split("\t", 1)[0]
    if value == "/dev/null":
        return True, None
    if not value.startswith(prefix):
        return False, None
    return True, value[len(prefix):]


CONTROL_ESCAPES = {"\n": "\\n", "\r": "\\r", "\t": "\\t"}


def safe_path(path):
    """Render a path so it cannot forge output rows.

    Git C-quotes control characters in names; decoding them back and interpolating the
    result would let a filename containing a newline print what looks like a counted
    fact line of its own.
    """
    out = []
    for char in path:
        if char in CONTROL_ESCAPES:
            out.append(CONTROL_ESCAPES[char])
        elif ord(char) < 32 or ord(char) == 127:
            out.append("\\x%02x" % ord(char))
        else:
            out.append(char)
    return "".join(out)


def path_kind(path):
    basename = os.path.basename(path)
    segments = path.split("/")
    for kind, rules in FILE_KIND_RULES.items():
        if any(segment in rules.get("path_segments", ()) for segment in segments):
            return kind
        if any(part in basename for part in rules.get("basename_contains", ())):
            return kind
        if basename in rules.get("basenames", ()):
            return kind
        if basename.startswith(rules.get("basename_prefixes", ())):
            return kind
        if basename.endswith(rules.get("basename_suffixes", ())):
            return kind
        if any(part in path for part in rules.get("path_contains", ())):
            return kind
    return "source"


def paths_from_diff_header(raw):
    """Return (valid, old path, new path) from a diff --git header."""
    if not raw.startswith("diff --git "):
        return False, None, None
    operands = raw[len("diff --git "):]
    if operands.startswith('"'):
        old_value, trailing = unquote_git_path(operands)
        if old_value is None or not trailing.startswith(" "):
            return False, None, None
        new_value, trailing = unquote_git_path(trailing[1:])
        if new_value is None or trailing:
            return False, None, None
    else:
        # Git leaves spaces unquoted.  The two operands are nevertheless delimited
        # by the second path's b/ prefix, not by every whitespace character.
        candidates = []
        for marker in (" b/", ' "b/'):
            start = 0
            while True:
                position = operands.find(marker, start)
                if position < 0:
                    break
                candidates.append(position)
                start = position + 1
        old_value = new_value = None
        for position in sorted(candidates, reverse=True):
            old_candidate = operands[:position]
            new_candidate, trailing = unquote_git_path(operands[position + 1:])
            if old_candidate.startswith("a/") and new_candidate is not None and not trailing:
                old_value, new_value = old_candidate, new_candidate
                break
        if old_value is None:
            return False, None, None
    valid_old, old = path_from_header(old_value, "a/")
    valid_new, new = path_from_header(new_value, "b/")
    return valid_old and valid_new, old, new


def finish_entry(entries, entry):
    """Append readable entries and count unreadable ones."""
    if entry is None:
        return 0
    if entry["combined"]:
        entries.append(entry)
        return 0
    if (entry["unreadable"] or entry["header_invalid"] or entry["in_hunk"]
            or entry["old_seen"] != entry["new_seen"]):
        return 1
    entries.append(entry)
    return 0


def empty_entry(position, old=None, new=None):
    return {
        "old": old, "new": new, "old_seen": False, "new_seen": False,
        "lines": [], "position": position, "new_file": False,
        "deleted_file": False, "renamed": False, "in_hunk": False,
        "old_remaining": 0, "new_remaining": 0, "unreadable": False,
        "combined": False, "header_invalid": False,
    }


def parse_diff(text):
    entries = []
    entry = None
    unreadable = 0
    for position, raw in enumerate(text.splitlines()):
        if raw.startswith("diff --git "):
            unreadable += finish_entry(entries, entry)
            valid, old, new = paths_from_diff_header(raw)
            entry = empty_entry(position, old, new)
            entry["header_invalid"] = not valid
            continue
        if raw.startswith("diff --cc ") or raw.startswith("diff --combined "):
            unreadable += finish_entry(entries, entry)
            entry = empty_entry(position)
            entry["combined"] = True
            continue
        if raw.startswith("--- ") and not (entry is not None and entry["in_hunk"]):
            if entry is not None and entry["old_seen"] and entry["new_seen"]:
                unreadable += finish_entry(entries, entry)
                entry = None
            if entry is None:
                entry = empty_entry(position)
            valid, entry["old"] = path_from_header(raw[4:], "a/")
            if not valid:
                entry["unreadable"] = True
            entry["old_seen"] = True
            continue
        if raw.startswith("+++ ") and not (entry is not None and entry["in_hunk"]):
            if entry is None:
                entry = empty_entry(position)
                entry["unreadable"] = True
            valid, entry["new"] = path_from_header(raw[4:], "b/")
            if not valid:
                entry["unreadable"] = True
            entry["new_seen"] = True
            if entry["old_seen"] and valid:
                # Content headers are authoritative when an unquoted diff header is
                # ambiguous because either pathname itself contains " b/".
                entry["header_invalid"] = False
            continue
        if entry is None:
            continue
        if raw == "new file mode" or raw.startswith("new file mode "):
            entry["new_file"] = True
        elif raw == "deleted file mode" or raw.startswith("deleted file mode "):
            entry["deleted_file"] = True
        elif raw.startswith(("rename from ", "rename to ", "copy from ", "copy to ")):
            # One unambiguous path per line. The `diff --git` header carries both
            # operands with no delimiter git escapes, so a directory literally named
            # `dir b` makes that header ambiguous; these lines never are, so they win.
            keyword, _, operand = raw.partition(" from ")
            if not operand:
                keyword, _, operand = raw.partition(" to ")
                target = "new"
            else:
                target = "old"
            decoded, trailing = unquote_git_path(operand) if operand.startswith('"') else (operand, "")
            if decoded is not None and not trailing:
                entry[target] = decoded
            if raw.startswith("rename "):
                entry["renamed"] = True
        elif entry["combined"] and raw.startswith("@@@"):
            # Combined hunks have one old range per parent. Their line prefixes do
            # not have unified-diff addition/removal semantics, so count the entry
            # separately rather than presenting invented line totals.
            if not re.match(r"^@@@ (?:-\d+(?:,\d+)? )+\+\d+(?:,\d+)? @@@", raw):
                entry["unreadable"] = True
        elif raw.startswith("@@"):
            hunk = re.match(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@", raw)
            if hunk is None:
                entry["unreadable"] = True
                continue
            entry["in_hunk"] = True
            entry["old_remaining"] = int(hunk.group(1) or 1)
            entry["new_remaining"] = int(hunk.group(2) or 1)
        elif entry["in_hunk"] and raw[:1] in ("+", "-"):
            entry["lines"].append((position, raw))
            if raw.startswith("+"):
                entry["new_remaining"] -= 1
            else:
                entry["old_remaining"] -= 1
            if entry["old_remaining"] < 0 or entry["new_remaining"] < 0:
                entry["unreadable"] = True
            if entry["old_remaining"] == 0 and entry["new_remaining"] == 0:
                entry["in_hunk"] = False
        elif entry["in_hunk"] and raw.startswith(" "):
            entry["old_remaining"] -= 1
            entry["new_remaining"] -= 1
            if entry["old_remaining"] < 0 or entry["new_remaining"] < 0:
                entry["unreadable"] = True
            if entry["old_remaining"] == 0 and entry["new_remaining"] == 0:
                entry["in_hunk"] = False
    unreadable += finish_entry(entries, entry)
    if not entries and not unreadable:
        return None
    return entries, unreadable


def render(entries, unreadable):
    combined = sum(entry["combined"] for entry in entries)
    entries = [entry for entry in entries if not entry["combined"]]
    if not entries:
        notices = []
        if unreadable:
            notices.append(f"- {unreadable:,} diff entries were unreadable")
        if combined:
            notices.append(f"- {combined:,} combined diff entries were not line-counted")
        return "\n".join(notices) + ("\n" if notices else "")
    additions = removals = 0
    paths = []
    manifest = []
    guards = []
    test_added = test_removed = 0
    new_files = deleted_files = renamed_files = 0

    for entry in entries:
        path = entry["new"] or entry["old"]
        paths.append((path, entry["position"]))
        is_new = entry["new_file"] or entry["old"] is None
        is_deleted = entry["deleted_file"] or entry["new"] is None
        if is_new:
            new_files += 1
        if is_deleted:
            deleted_files += 1
        if entry["renamed"]:
            renamed_files += 1
        dependency_added = dependency_removed = 0
        for position, line in entry["lines"]:
            body = line[1:]
            if line.startswith("+"):
                additions += 1
                if any(pattern in body for pattern in TEST_DECLARATION_PATTERNS):
                    test_added += 1
                if os.path.basename(path) in MANIFEST_BASENAMES and DEPENDENCY_ENTRY_RE.search(body):
                    dependency_added += 1
            else:
                removals += 1
                if any(pattern in body for pattern in TEST_DECLARATION_PATTERNS):
                    test_removed += 1
                if os.path.basename(path) in MANIFEST_BASENAMES and DEPENDENCY_ENTRY_RE.search(body):
                    dependency_removed += 1
                if any(pattern in body.lower() for pattern in GUARD_PATTERNS):
                    guards.append((path, position, line.rstrip()[:100]))
        if dependency_added or dependency_removed:
            manifest.append((path, entry["position"], dependency_added, dependency_removed))

    kinds = {}
    for path, position in paths:
        kind = path_kind(path)
        kinds[kind] = kinds.get(kind, 0) + 1
    kind_text = ", ".join(f"{kind} {count:,}" for kind, count in kinds.items())
    lines = [
        "## Change scan",
        "",
    ]
    if unreadable:
        lines.append(f"- {unreadable:,} diff entries were unreadable")
    if combined:
        lines.append(f"- {combined:,} combined diff entries were not line-counted")
    lines.append(f"- {len(paths):,} files changed, +{additions:,}/-{removals:,}")
    if kind_text:
        lines.append(f"- by path pattern: {kind_text}")
    lines.append(
        f"- new files {new_files:,}, deleted {deleted_files:,}, renamed {renamed_files:,}"
    )
    if manifest:
        lines.extend(["", "### Manifest-line matches", "- Pattern list: manifest-line regular expressions"])
        for path, _, added, removed in sorted(manifest, key=lambda item: (item[0], item[1])):
            lines.append(f"- {safe_path(path)}: +{added:,}/-{removed:,} matched lines")
    if guards:
        lines.extend(["", "### Removed-line matches", "- Pattern list: removed-line substrings (case-insensitive)"])
        for path, _, line in sorted(guards, key=lambda item: (item[0], item[1]))[:15]:
            lines.append(f"- {safe_path(path)}:{line}")
        if len(guards) > 15:
            lines.append(f"- ... and {len(guards) - 15:,} more")
    if test_added or test_removed:
        lines.extend(["", "### Test-pattern matches", "- Pattern list: test-pattern substrings (case-sensitive)", f"- +{test_added:,}/-{test_removed:,} matched lines"])
    return "\n".join(lines) + "\n"


def arguments(argv):
    minimum = 200
    values = list(argv[1:])
    if len(values) == 1:
        return minimum, values[0], None
    if len(values) == 3 and values[0] == "--min-lines":
        try:
            minimum = int(values[1])
        except ValueError:
            return None, None, "--min-lines must be a non-negative integer"
        if minimum < 0:
            return None, None, "--min-lines must be a non-negative integer"
        return minimum, values[2], None
    return None, None, "usage: diffscan.py [--min-lines N] <path|->"


def main(argv):
    minimum, path, error = arguments(argv)
    if error:
        print(f"diffscan: {error}", file=sys.stderr)
        return 2
    try:
        if path == "-":
            # sys.stdin.read() inherits surrogateescape, so undecodable bytes would slip
            # past the operational-failure path and be scanned as if they were text.
            text = sys.stdin.buffer.read().decode("utf-8")
        else:
            with open(path, encoding="utf-8") as source:
                text = source.read()
    except OSError as exc:
        print(f"diffscan: cannot read {path!r}: {exc.strerror or exc}", file=sys.stderr)
        return 1
    except UnicodeError as exc:
        print(f"diffscan: cannot decode {path!r}: {exc}", file=sys.stderr)
        return 1
    parsed_diff = parse_diff(text)
    if parsed_diff is None:
        return 0
    entries, unreadable = parsed_diff
    changed_lines = sum(len(entry["lines"]) for entry in entries)
    if changed_lines < minimum:
        return 0
    sys.stdout.write(render(entries, unreadable))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
