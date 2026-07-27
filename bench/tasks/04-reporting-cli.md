# Task 04 - reporting layer and CLI (shape: multi-file feature)

The ledger can be parsed and aggregated but never shown. Build the output side.

Required behaviour:

1. New `ledger/filters.py`:
   - `by_currency(records, currency)` - case-insensitive.
   - `by_date_range(records, since=None, until=None)` - inclusive on both ends, either
     bound optional, both accepting `datetime.date`.
   - Both return a new list and never mutate their input.

2. New `ledger/report.py`:
   - `render_table(records)` - a column-aligned text table with a header row
     (`day`, `label`, `amount`, `currency`). Columns are padded to the widest cell in
     that column. Amounts show two decimals.
   - `render_csv(records)` - RFC4180 CSV with that same header, produced with the
     `csv` module, `\n` line endings, no trailing blank line.
   - `render_json(records)` - a JSON array of objects, dates as ISO strings, sorted by
     day then label, indented by 2.
   - Every renderer returns a string and handles an empty record list without raising
     (header only for table and csv, `[]` for json).

3. New `ledger/cli.py`, runnable as `python3 -m ledger.cli`:
   - Usage: `ledger.cli FILE [--currency C] [--since YYYY-MM-DD] [--until YYYY-MM-DD]
     [--format table|csv|json] [--totals]`, built with `argparse`.
   - Reads the file, parses it with `parse_lines`, applies whichever filters were
     given, then prints in the chosen format (`table` is the default).
   - `--totals` prints `total_by_currency` output instead of the rows, one
     `CURRENCY: amount` line per currency, sorted by currency, amounts to two decimals.
   - A `ParseError` in the input exits with status 1 and a message on stderr naming the
     offending line number. A missing file exits 1 the same way. Success exits 0.
   - A `main(argv=None)` function returns the exit status so tests can call it without
     spawning a process.

4. Tests for all three modules, at least 15 new test methods, covering: each filter
   including its boundaries and the no-mutation guarantee, each renderer including the
   empty-input case, the CLI's default format, `--totals`, a combined
   currency-and-date-range filter, and both failure exits.

5. The existing 12 tests keep passing unchanged.

Do not add dependencies - standard library only.

Check command: `python3 -m unittest discover -s . -t .` - all tests pass.
