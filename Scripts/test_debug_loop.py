"""Tests that the host verdict rejects false business success."""
import base64
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import urllib.error
from debug_loop import decode_screenshot, run_save, run_screenshot, wait_ready, forward_usb


class ScenarioClient:
    def __init__(self, corrupt=False):
        self.corrupt = corrupt
        self.session = 0
        self.saved = False
        self.text = ""

    def request(self, method, path, payload=None):
        if path == "/session":
            self.session += 1
            self.saved = False
            return {"runID": str(self.session)}
        if path == "/snapshot":
            return {"runID": str(self.session),
                    "model": {"state": "saved" if self.saved else "editing", "reflectionID": "r"},
                    "persistence": {"count": int(self.saved), "texts": ["WRONG" if self.corrupt else self.text] if self.saved else [],
                                    "reflectionIDs": ["r"] if self.saved else [], "discussionCount": int(self.saved)}}
        if path == "/actions":
            return self.result
        if path == "/events?after=0":
            return {"events": [{"actionID": "a", "name": n} for n in ["action.started", "reflection.save.returned"]]}
        raise AssertionError(path)

    def action(self, text):
        self.text = text
        self.saved = bool(text.strip())
        self.result = {"status": "completed" if self.saved else "rejected"}
        return "a", self.result


class VerdictTests(unittest.TestCase):
    def test_old_build_reports_upgrade_instead_of_requesting_token(self):
        class OldClient:
            def request(self, *args):
                raise urllib.error.HTTPError("local", 401, "Unauthorized", {}, None)
        with self.assertRaisesRegex(RuntimeError, "old token build"):
            wait_ready(OldClient(), 0)

    @patch("debug_loop.subprocess.Popen")
    @patch("debug_loop.subprocess.check_output", return_value="device-1\n")
    @patch("debug_loop.shutil.which", return_value="tool")
    @patch("debug_loop.socket.create_connection", side_effect=OSError)
    def test_missing_forward_starts_usb_process(self, connection, which, devices, process):
        forward_usb()
        self.assertEqual(process.call_args.args[0], ["iproxy", "-u", "device-1", "18765:18765"])

    @patch("debug_loop.subprocess.Popen")
    @patch("debug_loop.socket.create_connection")
    def test_existing_forward_is_reused(self, connection, process):
        forward_usb()
        process.assert_not_called()

    def test_consistent_three_source_result_passes(self):
        run_save(ScenarioClient(), {})

    def test_ui_success_with_wrong_persistence_fails(self):
        with self.assertRaisesRegex(AssertionError, "Persisted text differs"):
            run_save(ScenarioClient(corrupt=True), {})


class ScreenshotTests(unittest.TestCase):
    def payload(self, raw):
        return {"scale": 2.0, "width": 393.0, "height": 852.0, "bytes": len(raw),
                "png": base64.b64encode(raw).decode()}

    def test_real_png_is_written_to_the_run_directory(self):
        raw = b"\x89PNG\r\n\x1a\n" + b"payload"
        with tempfile.TemporaryDirectory() as directory:
            evidence = run_screenshot(StubClient(self.payload(raw)), Path(directory), 2)
            self.assertEqual(Path(evidence["path"]).read_bytes(), raw)
            self.assertEqual(evidence["bytes"], len(raw))

    def test_http_200_without_a_real_png_fails(self):
        for payload in [{"scale": 2.0}, {"png": "not base64!!"},
                        self.payload(b"not a png at all")]:
            with self.assertRaises(AssertionError):
                decode_screenshot(payload)


class StubClient:
    def __init__(self, payload):
        self.payload = payload
        self.path = None

    def request(self, method, path, payload=None):
        self.path = path
        return self.payload


if __name__ == "__main__":
    unittest.main()
