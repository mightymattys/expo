"""Parse raw expense lines into records.

A line looks like:  2026-01-02;coffee;3.50;EUR
Blank lines and lines starting with '#' are comments.
"""

from datetime import date

SEPARATOR = ";"
KNOWN_CURRENCIES = ("EUR", "USD", "CZK")


class ParseError(ValueError):
    """A line that cannot be turned into a record."""


def _parse_day(raw):
    try:
        return date.fromisoformat(raw)
    except ValueError:
        raise ParseError(f"not a date: {raw!r}")


def _parse_amount(raw):
    try:
        return float(raw)
    except ValueError:
        raise ParseError(f"not an amount: {raw!r}")


def parse_line(line):
    """Return a record dict, or None for a comment/blank line."""
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None

    fields = stripped.split(SEPARATOR)
    if len(fields) != 4:
        raise ParseError(f"expected 4 fields, got {len(fields)}: {stripped!r}")

    day, label, amount, currency = (f.strip() for f in fields)
    if not label:
        raise ParseError("label must not be empty")
    currency = currency.upper()
    if currency not in KNOWN_CURRENCIES:
        raise ParseError(f"unknown currency: {currency!r}")

    return {
        "day": _parse_day(day),
        "label": label,
        "amount": _parse_amount(amount),
        "currency": currency,
    }


def parse_lines(lines):
    """Parse an iterable of lines, skipping comments and blanks."""
    records = []
    for line in lines:
        record = parse_line(line)
        if record is not None:
            records.append(record)
    return records
