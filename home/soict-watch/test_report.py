"""Run with: python3 -m unittest discover -s home/soict-watch"""

from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from report import load_report, slack_payload, validate_slack_payload


class ReportLimitsTest(unittest.TestCase):
    def test_slack_boundaries(self):
        payload = slack_payload({"categories": [{"title": "登録", "sections": ["変更"]}]})
        cases = [
            ("fallback", 40000, lambda p, n: p.update(text="あ" * n)),
            ("section", 3000, lambda p, n: p["blocks"][0]["text"].update(text="あ" * n)),
            ("title", 150, lambda p, n: p["blocks"][1]["title"].update(text="あ" * n)),
            ("children", 10, lambda p, n: p["blocks"][1].update(
                child_blocks=[deepcopy(p["blocks"][0]) for _ in range(n)])),
            ("blocks", 50, lambda p, n: p.update(
                blocks=[deepcopy(p["blocks"][0]) for _ in range(n)])),
            ("nested section", 3000, lambda p, n:
             p["blocks"][1]["child_blocks"][0]["text"].update(text="あ" * n)),
        ]
        for name, limit, mutate in cases:
            with self.subTest(name=name):
                candidate = deepcopy(payload)
                mutate(candidate, limit)
                validate_slack_payload(candidate)
                mutate(candidate, limit + 1)
                with self.assertRaises(ValueError):
                    validate_slack_payload(candidate)

    def test_shared_loader_checks_constructed_payload(self):
        report = {"categories": [{"title": "登録", "sections": ["変更"]}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "response.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            self.assertEqual(load_report(path), report)
            payload = slack_payload(report)
            payload["blocks"][1]["title"]["text"] = "あ" * 151
            with patch("report.slack_payload", return_value=payload):
                with self.assertRaisesRegex(ValueError, "150-character"):
                    load_report(path)


if __name__ == "__main__":
    unittest.main()
