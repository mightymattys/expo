import unittest
from datetime import date

from ledger.aggregate import busiest_day, total_by_currency, total_by_label

RECORDS = [
    {"day": date(2026, 1, 2), "label": "coffee", "amount": 3.5, "currency": "EUR"},
    {"day": date(2026, 1, 2), "label": "bus", "amount": 1.2, "currency": "EUR"},
    {"day": date(2026, 1, 3), "label": "coffee", "amount": 90.0, "currency": "CZK"},
]


class AggregateTests(unittest.TestCase):
    def test_total_by_currency(self):
        self.assertEqual(total_by_currency(RECORDS), {"EUR": 4.7, "CZK": 90.0})

    def test_total_by_label(self):
        self.assertEqual(
            total_by_label(RECORDS),
            {"coffee": {"EUR": 3.5, "CZK": 90.0}, "bus": {"EUR": 1.2}},
        )

    def test_busiest_day(self):
        self.assertEqual(busiest_day(RECORDS), date(2026, 1, 2))

    def test_busiest_day_of_nothing(self):
        self.assertIsNone(busiest_day([]))


if __name__ == "__main__":
    unittest.main()
