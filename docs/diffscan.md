# diffscan

`scripts/diffscan.py` reads one unified diff from a file path or standard input. It
does not read a repository or run git. It prints a block only when the counted added
and removed lines meet `--min-lines` (default `200`). It prints nothing only for empty
input, input with no recognisable diff entries, or input below that threshold.

Entries with usable `diff --git` metadata are counted even when they have no content
headers or hunks, including empty added or deleted files, binary changes, mode-only
changes, and pure renames. Git's quoted C-style paths and unquoted paths containing
spaces are decoded for display. An entry that cannot be read is skipped without
preventing the rest of the diff from being scanned. In a printed block, its
`- N diff entries were unreadable` line appears before totals; when all entries were
skipped, that count is the only output. Combined entries (`diff --cc` and
`diff --combined`) are reported as `combined diff entries were not line-counted`: their
multi-parent hunk prefixes are not unified-diff addition/removal counts.

Invalid arguments and unreadable or non-UTF-8 input are operational failures: they
write one factual line to standard error and exit non-zero. The three silent-success
cases remain empty input, input with no recognisable diff entries, and input below the
threshold.

Its contract is counts and literal pattern hits only. The output does not state what a
change means.

## Change scan

The first row counts readable diff entries and added and removed hunk lines. The kind
row uses the new path, or the old path for deleted files, and the first matching rule
below. The final row counts `new file mode`, `deleted file mode`, and `rename from` or
`rename to` diff metadata.

The path-kind table, in order, is:

- `tests`: path segment `test`, `tests`, `spec`, or `__tests__`; basename containing
  `test` or `spec`.
- `config`: basename `package.json`, `tsconfig.json`, `pyproject.toml`, `Cargo.toml`,
  `go.mod`, `Makefile`, or `Dockerfile`; basename prefix `.eslintrc`; basename suffix
  `.yml`, `.yaml`, `.toml`, or `.ini`.
- `docs`: basename suffix `.md`, `.rst`, or `.txt`.
- `generated`: basename suffix `.lock` or `-lock.json`; path containing
  `node_modules`, `vendor`, `dist`, or `build`.
- `source`: every remaining path.

## Manifest-line matches

For `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, and
`requirements.txt`, this section identifies itself with `Pattern list: manifest-line
regular expressions` and counts added and removed lines matching one of these regular
expressions:

```
^\s*["'][^"']+["']\s*[:=]\s*["']?[<>=~^v*0-9]
^\s*[A-Za-z0-9_.@/+-]+\s*(?:==|>=|<=|~=|!=|=|>|<)\s*[v0-9]
^\s*[A-Za-z0-9_.@/+-]+\s+[v0-9][A-Za-z0-9_.+<>=~^*-]*
^\s*gem\s+["'][^"']+["']\s*,\s*["']?[<>=~^v0-9]
```

## Removed-line matches

This section identifies itself with `Pattern list: removed-line substrings
(case-insensitive)`. It lists removed lines containing one of these substrings:
`catch`, `except`, `finally`, `rescue`, `throw`, `raise`, `assert`, `validate`,
`if err != nil`, `panic`, `authoriz`, `authent`, `permission`, `sanitize`, `escape`.
It prints the first 15 after path and appearance ordering, with each diff line capped
at 100 characters, then a count for remaining matches.

## Test-pattern matches

This section identifies itself with `Pattern list: test-pattern substrings
(case-sensitive)`. It counts added and removed lines containing these case-sensitive
literal substrings: `def test_`, `it(`, `test(`, `describe(`, `func Test`, `#[test]`,
`@Test`.

Within each section, rows order by path and then their first appearance in the diff.

## Fixture exceptions

Every fixture is generated from a temporary Git repository. `diffscan-combined.diff`
is emitted by `git show --cc` for a merge commit; Git does not accept a combined diff
as a standalone `git apply` patch, so `scripts/check.sh` asserts that documented
exception separately.

## What a path is allowed to do

A path is data, never formatting. Git C-quotes control characters in file names, so a
decoded name can contain a newline; every path is re-escaped before it reaches an output
row, and a file name therefore cannot produce a line that looks like a counted fact.

The `by path pattern` row groups files by which path rule matched first. A group name is
the name of the rule, not a claim about the file: `contest.py` falls in the `tests` group
because its basename contains `test`, which is what the rule tests for and all it means.

Input read from `-` is decoded as strict UTF-8, like a file: undecodable bytes are an
operational failure with a non-zero exit, not something to scan as if it were text.
