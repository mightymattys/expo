import unittest
from datetime import date

from ledger.parse import ParseError, parse_line, parse_lines


class ParseLineTests(unittest.TestCase):
    def test_parses_a_full_line(self):
        record = parse_line("2026-01-02;coffee;3.50;EUR")
        self.assertEqual(record["day"], date(2026, 1, 2))
        self.assertEqual(record["label"], "coffee")
        self.assertEqual(record["amount"], 3.50)
        self.assertEqual(record["currency"], "EUR")

    def test_trims_whitespace(self):
        record = parse_line("  2026-01-02 ; coffee ; 3.50 ; eur  ")
        self.assertEqual(record["label"], "coffee")
        self.assertEqual(record["currency"], "EUR")

    def test_skips_comments_and_blanks(self):
        self.assertIsNone(parse_line(""))
        self.assertIsNone(parse_line("   "))
        self.assertIsNone(parse_line("# a note"))

    def test_rejects_wrong_field_count(self):
        with self.assertRaises(ParseError):
            parse_line("2026-01-02;coffee;3.50")

    def test_rejects_bad_date(self):
        with self.assertRaises(ParseError):
            parse_line("2026-13-99;coffee;3.50;EUR")

    def test_rejects_unknown_currency(self):
        with self.assertRaises(ParseError):
            parse_line("2026-01-02;coffee;3.50;GBP")

    def test_rejects_empty_label(self):
        with self.assertRaises(ParseError):
            parse_line("2026-01-02;;3.50;EUR")


class ParseLinesTests(unittest.TestCase):
    def test_collects_only_records(self):
        lines = ["# header", "", "2026-01-02;coffee;3.50;EUR", "2026-01-03;bus;1.20;EUR"]
        self.assertEqual(len(parse_lines(lines)), 2)


if __name__ == "__main__":
    unittest.main()
