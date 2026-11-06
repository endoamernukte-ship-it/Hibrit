"""Static smoke checks only; these do not replace MetaEditor or MT5 tests."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "Forex_Dynamic_Engine.mq5").read_text(encoding="utf-8")
ORIGINAL = (ROOT / "SqueezeMomentum_LB_EA.mq5").read_text(encoding="utf-8")


def squeeze_core(text):
    end = "int LoadRates(" if text is ORIGINAL else "// Read exactly one CLOSED indicator value"
    return text[text.index("double LinearRegressionEnd"):text.index(end)].strip()


class SourceSmokeTests(unittest.TestCase):
    def test_original_squeeze_core_preserved(self):
        self.assertEqual(squeeze_core(ORIGINAL), squeeze_core(SOURCE))

    def test_required_entry_points_and_safe_default(self):
        for name in ("DetectMarketRegime", "CalculateDynamicGrid", "ManageHedgingAndScalp", "ProcessClosedBar", "OnTick"):
            self.assertRegex(SOURCE, rf"\b{name}\s*\(")
        self.assertRegex(SOURCE, r"InpAllowTrading\s*=\s*false")
        self.assertIn("ACCOUNT_MARGIN_MODE_RETAIL_HEDGING", SOURCE)

    def test_delimiters_balanced_after_comments_and_strings(self):
        text = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', '', SOURCE, flags=re.S)
        stack = []
        pairs = {')': '(', ']': '[', '}': '{'}
        for char in text:
            if char in '([{':
                stack.append(char)
            elif char in pairs:
                self.assertTrue(stack, f"unexpected {char}")
                self.assertEqual(stack.pop(), pairs[char])
        self.assertEqual(stack, [])


if __name__ == "__main__":
    unittest.main()
