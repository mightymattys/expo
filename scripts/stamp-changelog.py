#!/usr/bin/env python3
# Turn the changelog's "## Unreleased" heading into a dated release heading.
# A separate script rather than inline in release.sh so CI can fixture-test it:
# 0.7.9 and 0.7.10 both shipped with their entry still titled "Unreleased".
# On any refusal the file is left untouched and the reason goes to stderr.
import json
import re
import sys
from datetime import datetime, timezone

if len(sys.argv) not in (2, 3):
    sys.exit("usage: stamp-changelog.py <version> [changelog-path]")

version = sys.argv[1]
path = sys.argv[2] if len(sys.argv) == 3 else "CHANGELOG.md"
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    sys.exit(f"not a version: {version}")

try:
    with open(path, encoding="utf-8") as source:
        text = source.read()
except OSError as exc:
    sys.exit(f"cannot read {path}: {exc}")

match = re.search(r"^## +Unreleased *(?P<rest>.*)$", text, re.MULTILINE)
if not match:
    sys.exit(f"{path} has no '## Unreleased' entry - write one before releasing")

# A heading may carry the intended version, a title, both, or neither:
#   ## Unreleased - 0.7.11 - the benchmark harness
#   ## Unreleased - 0.7.9
#   ## Unreleased - some title
#   ## Unreleased
rest = re.sub(r"^-\s*", "", match.group("rest").strip())
declared = re.match(r"^(\d+\.\d+\.\d+)\b\s*-?\s*", rest)
title = rest
if declared:
    if declared.group(1) != version:
        sys.exit(
            f"{path} Unreleased entry names {declared.group(1)}, "
            f"but this release is {version}"
        )
    title = rest[declared.end():].strip()

heading = f"## {version} - {datetime.now(timezone.utc).date().isoformat()}"
if title:
    heading += f" - {title}"

try:
    with open(path, "w", encoding="utf-8") as target:
        target.write(text[:match.start()] + heading + text[match.end():])
except OSError as exc:
    sys.exit(f"cannot write {path}: {exc}")
print(heading)
