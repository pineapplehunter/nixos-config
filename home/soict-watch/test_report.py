"""Run with: python3 -m unittest discover -s home/soict-watch"""

from copy import deepcopy
import datetime
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from report import GroupReport, load_report, slack_payload, validate_slack_payload
from monitor import main


class ReportLimitsTest(unittest.TestCase):
    def test_no_reportable_changes_notifies_discord_and_updates_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / str(datetime.date.today().year)
            state.mkdir()
            baseline = state / "baseline.json"
            baseline.write_text(json.dumps({"https://soict.org/": "Program Committees\n"}))
            snapshot = {"https://soict.org/": "Program Committee\n"}

            report = {"recipient": "admin", "reason": "見出しの単数形への修正のみのため投稿不要です。https://soict.org/"}

            def review(*args, **kwargs):
                (state / "response.json").write_text(json.dumps(report), encoding="utf-8")

            with patch.dict("os.environ", {
                "SOICT_STATE_DIR": directory, "SOICT_REPORT_EXTENSION": "unused",
            }), patch("monitor.crawl", return_value=snapshot), patch(
                "monitor.subprocess.run", side_effect=review,
            ), patch("monitor.notify_discord") as notify, patch("monitor.urlopen") as send:
                main()
            notify.assert_called_once_with(report["reason"])
            self.assertEqual(load_report(state / "response.json").model_dump(), report)
            self.assertEqual(json.loads(baseline.read_text()), snapshot)
            send.assert_not_called()
            self.assertFalse((state / "payload.json").exists())

    def test_unchanged_site_skips_notification_and_review(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / str(datetime.date.today().year)
            state.mkdir()
            snapshot = {"https://soict.org/": "unchanged\n"}
            (state / "baseline.json").write_text(json.dumps(snapshot))
            with patch.dict("os.environ", {"SOICT_STATE_DIR": directory}), patch(
                "monitor.crawl", return_value=snapshot,
            ), patch("monitor.notify_discord") as notify, patch("monitor.subprocess.run") as review:
                main()
            notify.assert_not_called()
            review.assert_not_called()

    def test_schema_requires_exactly_one_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "response.json"
            for report in [
                {}, {"categories": []}, {"recipient": "unknown", "reason": "不要"},
                {"recipient": "admin", "reason": " "},
                {"recipient": "admin", "reason": "不要", "categories": []},
                {"recipient": "group", "categories": []},
                {"recipient": "group", "reason": "不要"},
                {"recipient": "admin", "reason": 123},
                {"recipient": "slack", "categories": [{"title": "登録", "sections": ["変更"]}]},
                {"recipient": "discord", "reason": "不要"},
            ]:
                with self.subTest(report=report):
                    path.write_text(json.dumps(report), encoding="utf-8")
                    with self.assertRaises(ValueError):
                        load_report(path)

    def test_slack_boundaries(self):
        payload = slack_payload(GroupReport(
            recipient="group", categories=[{"title": "登録", "sections": ["変更"]}],
        ))
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
        report = {"recipient": "group", "categories": [{"title": "登録", "sections": ["変更"]}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "response.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            parsed = load_report(path)
            self.assertEqual(parsed.model_dump(), report)
            payload = slack_payload(parsed)
            payload["blocks"][1]["title"]["text"] = "あ" * 151
            with patch("report.slack_payload", return_value=payload):
                with self.assertRaisesRegex(ValueError, "150-character"):
                    load_report(path)


if __name__ == "__main__":
    unittest.main()
