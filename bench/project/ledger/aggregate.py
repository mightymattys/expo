"""Aggregate parsed records."""

from collections import defaultdict


def total_by_currency(records):
    """Sum amounts per currency."""
    totals = defaultdict(float)
    for record in records:
        totals[record["currency"]] += record["amount"]
    return dict(totals)


def total_by_label(records):
    """Sum amounts per label, per currency."""
    totals = defaultdict(lambda: defaultdict(float))
    for record in records:
        totals[record["label"]][record["currency"]] += record["amount"]
    return {label: dict(inner) for label, inner in totals.items()}


def busiest_day(records):
    """The day with the most records. Ties break on the earlier day."""
    counts = defaultdict(int)
    for record in records:
        counts[record["day"]] += 1
    if not counts:
        return None
    return min(counts, key=lambda day: (-counts[day], day))
