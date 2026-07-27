# Task 02 - reject impossible amounts (shape: bugfix + regression tests)

`ledger/parse.py::_parse_amount` uses `float()`, which accepts values the ledger
domain cannot represent. All of these are currently parsed without complaint:

    2026-01-02;coffee;-3.50;EUR
    2026-01-02;coffee;nan;EUR
    2026-01-02;coffee;inf;EUR
    2026-01-02;coffee;1e400;EUR

A negative expense, a NaN and an infinity all flow into `total_by_currency`, where
NaN silently poisons every total it touches.

Required behaviour:

1. `parse_line` raises `ParseError` for a negative amount, for NaN, and for any
   infinite value (including one produced by overflow such as `1e400`).
2. Zero stays valid.
3. Regression tests cover each rejected form above by name, plus zero still parsing.
4. The `ParseError` message names why the amount was rejected.

Do not add dependencies. Do not change unrelated validation.

Check command: `python3 -m unittest discover -s . -t .` - all tests pass.
