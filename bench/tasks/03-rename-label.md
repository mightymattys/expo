# Task 03 - rename label to category (shape: mechanical bulk edit)

The record key `label` is being renamed to `category` across the whole project.

Required behaviour:

1. Every record produced by `ledger/parse.py` carries `category` instead of `label`.
2. `ledger/aggregate.py::total_by_label` becomes `total_by_category`, and its
   returned mapping is keyed by category. No alias for the old name is kept.
3. The `ParseError` for an empty value says `category must not be empty`.
4. Every existing test is updated to the new vocabulary. No test is deleted, and the
   suite keeps the same number of tests.
5. No occurrence of the identifier `label` remains anywhere under `ledger/` or
   `tests/`.

Check commands, both must hold:
- `python3 -m unittest discover -s . -t .` - all tests pass.
- `grep -rn "label" ledger/ tests/` - no matches.
