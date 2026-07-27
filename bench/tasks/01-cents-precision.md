# Task 01 - cents precision (shape: feature + tests)

In `ledger/parse.py`, amounts are parsed with `float()` and kept as floats, so
`total_by_currency` accumulates binary rounding error and an input like `3.505` is
silently accepted at a precision the domain does not have.

Required behaviour:

1. `parse_line` adds a `cents` key to every record: the amount as an integer number
   of cents (`3.50` -> `350`, `90` -> `9000`).
2. An amount with more than two decimal places raises `ParseError`. `3.5`, `3.50`
   and `3` stay valid; `3.505` does not.
3. `ledger/aggregate.py` gains `total_cents_by_currency(records)` returning integer
   cent totals per currency. The existing float-based functions keep working
   unchanged.
4. New tests cover: the `cents` value for a two-decimal amount, for an integer
   amount, rejection of a three-decimal amount, and an integer cent total that a
   float sum would get wrong (for example `0.1 + 0.2` summing to exactly `30`).

Do not change the existing public behaviour of `parse_line` beyond adding the key.

Check command: `python3 -m unittest discover -s . -t .` - all tests pass.
