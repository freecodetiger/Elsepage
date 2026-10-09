"""Tests that the host verdict rejects false business success."""
import base64
import contextlib
import http.server
import io
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
import urllib.error
from debug_loop import (character_error_rate, decode_screenshot, main, normalize_text, run_save,
                        run_screenshot, run_transcribe, validate_contextual_strings,
                        wait_ready, forward_usb)


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


def manifest(directory, clips):
    path = Path(directory) / "clips.json"
    path.write_text(json.dumps({"clips": clips}))
    return path


class TranscribeStub:
    """Canned /transcribe responses, keyed by clip file name. `echo` overrides the
    contextual strings the device claims to have applied."""

    def __init__(self, transcripts, echo=None):
        self.transcripts = transcripts
        self.echo = echo

    def request(self, method, path, payload=None, timeout=None):
        self.assert_path(path)
        if payload["file"] not in self.transcripts:
            raise AssertionError(payload["file"])
        return {
            "file": payload["file"],
            "transcript": self.transcripts[payload["file"]],
            "contextualStrings": payload["contextualStrings"] if self.echo is None else self.echo,
        }

    def assert_path(self, path):
        if path != "/transcribe":
            raise AssertionError(path)


class CharacterErrorRateTests(unittest.TestCase):
    def test_identical_text_scores_zero(self):
        self.assertEqual(character_error_rate("我读到 post-modern 这个词", "我读到 post-modern 这个词"), 0.0)

    def test_case_and_whitespace_are_not_errors(self):
        self.assertEqual(character_error_rate("Post-Modern  Reading", "post-modern reading"), 0.0)

    def test_punctuation_still_counts(self):
        self.assertGreater(character_error_rate("他说：好。", "他说好"), 0.0)

    def test_a_latin_term_arriving_as_homophones_scores_high(self):
        """The failure this metric exists for: one mangled term, most of the line lost."""
        reference = "这段是 post-modern 的典型写法"
        hypothesis = "这段是波斯莫登的典型写法"
        self.assertGreater(character_error_rate(reference, hypothesis), 0.2)

    def test_empty_reference_does_not_divide_by_zero(self):
        self.assertEqual(character_error_rate("", ""), 0.0)
        self.assertEqual(character_error_rate("", "多了东西"), 1.0)


class TranscribeScenarioTests(unittest.TestCase):
    clips = [
        {"file": "a.m4a", "reference": "我读到 post-modern 这个词", "note": "中英混"},
        {"file": "b.m4a", "reference": "这本书讲地方财政"},
    ]

    def test_a_clean_run_reports_per_clip_error_rates(self):
        with tempfile.TemporaryDirectory() as directory:
            stub = TranscribeStub({"a.m4a": "我读到 post-modern 这个词",
                                   "b.m4a": "这本书讲地方财政"})
            summary = run_transcribe(stub, Path(directory), manifest(directory, self.clips),
                                     ["置身事内", "兰小欢"])
            self.assertEqual(summary["mean_character_error_rate"], 0.0)
            self.assertEqual(summary["exact_matches"], 2)
            self.assertEqual(summary["results"][0]["note"], "中英混")
            self.assertTrue((Path(directory) / "transcripts.json").exists())

    def test_a_dropped_bias_field_fails_even_though_transcripts_look_fine(self):
        """The echo is the only end-to-end proof the configuration reached the
        recognizer, so a missing field must not be recorded as a PASS."""
        with tempfile.TemporaryDirectory() as directory:
            stub = TranscribeStub({"a.m4a": "我读到 post-modern 这个词",
                                   "b.m4a": "这本书讲地方财政"}, echo=[])
            with self.assertRaises(AssertionError):
                run_transcribe(stub, Path(directory), manifest(directory, self.clips),
                               ["置身事内", "兰小欢"])

    def test_an_empty_transcript_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            stub = TranscribeStub({"a.m4a": "  ", "b.m4a": "这本书讲地方财政"})
            with self.assertRaises(AssertionError):
                run_transcribe(stub, Path(directory), manifest(directory, self.clips), [])

    def test_a_manifest_without_clips_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            stub = TranscribeStub({})
            with self.assertRaises(AssertionError):
                run_transcribe(stub, Path(directory), manifest(directory, []), [])


class ContextualStringValidationTests(unittest.TestCase):
    """The device alters an out-of-spec list, and the echo check would then blame
    the device for a client-side mistake, so the request is validated here."""

    def test_a_normal_list_passes(self):
        validate_contextual_strings(["置身事内", "兰小欢"])

    def test_an_over_long_entry_is_rejected_by_name(self):
        with self.assertRaises(AssertionError) as raised:
            validate_contextual_strings(["置身事内", "字" * 41])
        self.assertIn("字" * 41, str(raised.exception))

    def test_a_case_insensitive_duplicate_is_rejected(self):
        with self.assertRaises(AssertionError):
            validate_contextual_strings(["Keynesian", "keynesian"])

    def test_too_many_entries_is_rejected(self):
        with self.assertRaises(AssertionError):
            validate_contextual_strings(["术语%d" % i for i in range(101)])


class FakeDevice:
    """Serves the two routes the transcribe scenario touches."""

    def __init__(self, transcripts, echo=None):
        self.transcripts = transcripts
        self.echo = echo
        self.received = []

    def start(self):
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/status":
                    outer.respond(self, {"protocolVersion": 1, "actions": ["speech.transcribe"]})
                else:
                    outer.respond(self, {"error": "unknown_route"}, 404)

            def do_POST(self):
                payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                outer.received.append(payload)
                if self.path != "/transcribe":
                    outer.respond(self, {"error": "unknown_route"}, 404)
                    return
                outer.respond(self, {
                    "file": payload["file"],
                    "transcript": outer.transcripts[payload["file"]],
                    "contextualStrings": payload["contextualStrings"] if outer.echo is None else outer.echo,
                })

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        return "http://127.0.0.1:%d" % self.server.server_address[1]

    def respond(self, handler, value, code=200):
        body = json.dumps(value).encode()
        handler.send_response(code)
        handler.send_header("Content-Type", "application/json")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


class DriverEndToEndTests(unittest.TestCase):
    """Runs the real CLI against a fake device. The stub tests above bypass
    urllib, argument parsing and the run directory — which is where a driver
    actually breaks — and this half runs on this machine, so it should be proven
    before anyone spends an evening recording five clips."""

    clips = [{"file": "latest", "reference": "他说的 incentive 是制度设计的问题", "note": "中英混"}]

    def run_cli(self, base, directory, clips, extra=()):
        argv = ["debug_loop.py", "transcribe", "--base", base, "--output", str(directory),
                "--reference", str(manifest(directory, clips)), *extra]
        with patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as exit_reason:
                main()
        return exit_reason.exception.code

    def results(self, directory):
        found = list(Path(directory).glob("*/result.json"))
        self.assertEqual(len(found), 1, "Expected exactly one run directory")
        return json.loads(found[0].read_text()), found[0].parent

    def test_a_clean_run_records_evidence_and_exits_zero(self):
        device = FakeDevice({"latest": "他说的 incentive 是制度设计的问题"})
        try:
            base = device.start()
            with tempfile.TemporaryDirectory() as raw:
                code = self.run_cli(base, raw, self.clips,
                                    extra=["--contextual-strings", "置身事内,兰小欢"])
                self.assertEqual(code, 0)
                evidence, run_directory = self.results(raw)
                self.assertEqual(evidence["verdict"], "PASS")
                self.assertEqual(evidence["transcription"]["exact_matches"], 1)
                self.assertTrue((run_directory / "transcripts.json").exists())
                # The bias must survive the wire, not just be echoed back.
                self.assertEqual(device.received[0]["contextualStrings"], ["置身事内", "兰小欢"])
        finally:
            device.stop()

    def test_a_device_that_drops_the_bias_exits_nonzero(self):
        device = FakeDevice({"latest": "他说的 incentive 是制度设计的问题"}, echo=[])
        try:
            base = device.start()
            with tempfile.TemporaryDirectory() as raw:
                code = self.run_cli(base, raw, self.clips,
                                    extra=["--contextual-strings", "置身事内,兰小欢"])
                self.assertEqual(code, 1)
                evidence, _ = self.results(raw)
                self.assertEqual(evidence["verdict"], "FAIL")
                self.assertIn("not the requested", evidence["error"])
        finally:
            device.stop()

    def test_an_out_of_spec_bias_is_rejected_before_any_request(self):
        device = FakeDevice({"latest": "他说的 incentive 是制度设计的问题"})
        try:
            base = device.start()
            with tempfile.TemporaryDirectory() as raw:
                code = self.run_cli(base, raw, self.clips,
                                    extra=["--contextual-strings", "字" * 41])
                self.assertEqual(code, 1)
                self.assertEqual(device.received, [], "An out-of-spec request reached the device")
        finally:
            device.stop()


if __name__ == "__main__":
    unittest.main()
