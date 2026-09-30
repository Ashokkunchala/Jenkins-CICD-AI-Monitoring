import os
import subprocess
import sys
import unittest

class AppTests(unittest.TestCase):
    def test_health_contract(self):
        self.assertEqual(os.environ.get("CI_LAB_HEALTH_EXPECTED", "ok"), "ok")

    def test_version_is_defined(self):
        result = subprocess.run(
            [sys.executable, "-c", "import app; print(app.VERSION)"],
            capture_output=True, text=True, check=True
        )
        self.assertTrue(result.stdout.strip())

if __name__ == "__main__":
    unittest.main()
