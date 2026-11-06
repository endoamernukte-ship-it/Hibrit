"""Static smoke checks only; these do not replace MetaEditor or MT5 tests."""
import pathlib
import re
import shutil
import subprocess
import tempfile
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
        self.assertRegex(SOURCE, r"InpAllowTesterTrading\s*=\s*true")
        self.assertIn("ACCOUNT_MARGIN_MODE_RETAIL_HEDGING", SOURCE)

    def test_tester_permission_logic_compiled_from_actual_function(self):
        compiler = shutil.which("g++")
        if compiler is None:
            self.skipTest("g++ unavailable")
        start = SOURCE.index("bool TradingEnabled()")
        end = SOURCE.index("\nenum ENUM_DIAG", start)
        actual_function = SOURCE[start:end]
        harness = r"""
#include <cassert>
bool InpAllowTrading=false, InpAllowTesterTrading=true, is_tester=false;
const int MQL_TESTER=1;
int MQLInfoInteger(int) { return is_tester; }
""" + actual_function + r"""
int main() {
  for (int tester=0; tester<2; ++tester)
    for (int live=0; live<2; ++live)
      for (int test=0; test<2; ++test) {
        is_tester=tester; InpAllowTrading=live; InpAllowTesterTrading=test;
        assert(TradingEnabled() == (tester ? bool(test) : bool(live)));
      }
}
"""
        with tempfile.TemporaryDirectory() as path:
            cpp = pathlib.Path(path) / "test.cpp"
            exe = pathlib.Path(path) / "test"
            cpp.write_text(harness)
            subprocess.run([compiler, "-std=c++11", str(cpp), "-o", str(exe)], check=True)
            subprocess.run([str(exe)], check=True)

    def test_permission_guard_applies_to_open_close_and_cancel(self):
        open_body = SOURCE[SOURCE.index("bool OpenLayer("):SOURCE.index("bool CloseTicket(")]
        close_body = SOURCE[SOURCE.index("bool CloseTicket("):SOURCE.index("void SetFlatten(")]
        cancel_body = SOURCE[SOURCE.index("void CloseAllOurs("):SOURCE.index("void CloseHedges(")]
        self.assertIn("!TradingEnabled()", open_body)
        self.assertIn("!TradingEnabled()", close_body)
        self.assertIn("TradingEnabled()", cancel_body)

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
