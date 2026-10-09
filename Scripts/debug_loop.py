#!/usr/bin/env python3
"""ReadLoop DEBUG USB client: automatically establishes forwarding, no token required."""
import argparse
import base64
import binascii
import json
import shutil
import socket
import subprocess
from pathlib import Path
import time
import urllib.error
import urllib.request
import uuid


class Client:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def request(self, method, path, payload=None, timeout=12):
        data = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(self.base + path, data=data, method=method,
            headers={"Content-Type": "application/json"})
        with self.opener.open(request, timeout=timeout) as response:
            return json.load(response)

    def action(self, text):
        action_id = str(uuid.uuid4())
        result = self.request("POST", "/actions", {"id": action_id, "name": "reflection.submit", "text": text})
        deadline = time.monotonic() + 15
        while result["status"] == "running":
            if time.monotonic() >= deadline:
                raise TimeoutError("Action did not finish within 15 seconds")
            time.sleep(0.05)
            result = self.request("GET", "/actions/" + action_id)
        return action_id, result


def forward_usb(udid=None):
    """Reuse a live localhost forward; restart on the next invocation if it exited."""
    try:
        with socket.create_connection(("127.0.0.1", 18765), timeout=0.5):
            return
    except OSError:
        pass
    if not shutil.which("iproxy") or not shutil.which("idevice_id"):
        raise RuntimeError("Install USB tools first: brew install libimobiledevice")
    devices = subprocess.check_output(["idevice_id", "-l"], text=True, timeout=5).split()
    if udid is None:
        if len(devices) != 1:
            raise RuntimeError("Connect one trusted USB iPhone, or select it with --udid")
        udid = devices[0]
    elif udid not in devices:
        raise RuntimeError("Selected USB device is not connected")
    subprocess.Popen(["iproxy", "-u", udid, "18765:18765"],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def wait_ready(client, seconds):
    deadline = time.monotonic() + seconds
    last_error = "App unavailable"
    while True:
        try:
            status = client.request("GET", "/status")
            if status.get("protocolVersion") != 1:
                raise RuntimeError("Port is not a supported ReadLoop debug service")
            return status
        except urllib.error.HTTPError as error:
            if error.code == 401:
                raise RuntimeError("Device is running the old token build; install and launch the new DEBUG build") from error
            last_error = str(error)
        except (OSError, ValueError) as error:
            last_error = str(error)
        if time.monotonic() >= deadline:
            raise RuntimeError("Keep the DEBUG app open on the USB device: " + last_error)
        time.sleep(0.3)


def check(condition, message):
    if not condition:
        raise AssertionError(message)


PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def decode_screenshot(payload):
    """Base64 image -> PNG bytes. Rejects a 200 that carries no real PNG, so a
    device-side render failure can never be recorded as a visual PASS."""
    check(isinstance(payload, dict), "Screenshot payload is not an object")
    check(isinstance(payload.get("png"), str), "Screenshot payload has no image")
    try:
        raw = base64.b64decode(payload["png"], validate=True)
    except (binascii.Error, ValueError) as error:
        raise AssertionError("Screenshot is not valid base64: " + str(error)) from error
    check(raw.startswith(PNG_MAGIC), "Screenshot is not a PNG")
    return raw


def run_screenshot(client, directory, scale):
    payload = client.request("GET", "/screenshot?scale=%d" % scale)
    raw = decode_screenshot(payload)
    path = directory / "screenshot.png"
    path.write_bytes(raw)
    return {"scale": payload.get("scale"), "width": payload.get("width"),
            "height": payload.get("height"), "bytes": len(raw), "path": str(path)}


def normalize_text(text):
    """Case and whitespace are presentation, not recognition. Everything else —
    punctuation included — is kept, so a dropped or invented mark still counts."""
    return " ".join(text.split()).lower()


def character_error_rate(reference, hypothesis):
    """Levenshtein distance over characters, divided by the reference length.

    Characters rather than words because the failure being measured is a
    Latin-script term coming back as Chinese homophones: a word-level metric
    would score that mangling and a whole misheard clause as the same one error.
    """
    reference = normalize_text(reference)
    hypothesis = normalize_text(hypothesis)
    if not reference:
        return 0.0 if not hypothesis else 1.0
    previous = list(range(len(hypothesis) + 1))
    for i, ref_char in enumerate(reference, start=1):
        current = [i]
        for j, hyp_char in enumerate(hypothesis, start=1):
            current.append(min(
                previous[j] + 1,
                current[j - 1] + 1,
                previous[j - 1] + (ref_char != hyp_char),
            ))
        previous = current
    return previous[-1] / len(reference)


# Must track `SpeechRecognitionConfiguration` in Sources/SpeechCore. The device
# silently trims, dedupes and caps the list, so a request that breaks these rules
# comes back different — which below would be misread as a device fault.
MAX_CONTEXTUAL_STRINGS = 100
MAX_CONTEXTUAL_STRING_LENGTH = 40


def validate_contextual_strings(contextual_strings):
    """Rejects a request the device is documented to alter, naming the entry at
    fault. Without this, a client-side mistake surfaces as 'the device was biased
    with something else', which sends the investigation to the wrong side."""
    for phrase in contextual_strings:
        check(len(phrase) <= MAX_CONTEXTUAL_STRING_LENGTH,
              "Contextual string %r exceeds %d characters, so the device drops it; "
              "shorten it or remove it" % (phrase, MAX_CONTEXTUAL_STRING_LENGTH))
    lowered = [phrase.lower() for phrase in contextual_strings]
    check(len(set(lowered)) == len(lowered),
          "Contextual strings repeat an entry (case-insensitively), and the device collapses it: %r"
          % contextual_strings)
    check(len(contextual_strings) <= MAX_CONTEXTUAL_STRINGS,
          "More than %d contextual strings; the device keeps only the first %d"
          % (MAX_CONTEXTUAL_STRINGS, MAX_CONTEXTUAL_STRINGS))


def run_transcribe(client, directory, reference_path, contextual_strings):
    """Re-recognises unchanged clips, so a configuration change can be attributed
    to the configuration instead of to the speaker saying it differently.

    The assertions cover the mechanism: every clip returned a transcript, and the
    settings the device echoed back are the ones that were sent — that echo is the
    only end-to-end proof the configuration reached the recognizer. The error
    rates are reported, not asserted; no quality bar has been established yet, and
    inventing one would turn a measurement back into a guess.
    """
    manifest = json.loads(Path(reference_path).read_text())
    clips = manifest.get("clips") or []
    check(clips, "Reference manifest has no clips")
    requested_strings = [s.strip() for s in contextual_strings if s.strip()]
    validate_contextual_strings(requested_strings)
    requested = set(requested_strings)

    results = []
    for clip in clips:
        label = clip.get("file") or clip.get("path") or "?"
        payload = {"contextualStrings": contextual_strings}
        if clip.get("localeIdentifier"):
            payload["localeIdentifier"] = clip["localeIdentifier"]
        if clip.get("path"):
            # Uploading keeps the clip out of the app entirely: the device writes
            # it to its temp directory and deletes it, so no recording and no
            # database row is created for a measurement.
            source = Path(clip["path"])
            if not source.is_absolute():
                source = Path(reference_path).parent / source
            check(source.is_file(), "Clip %s not found at %s" % (label, source))
            payload["audioBase64"] = base64.b64encode(source.read_bytes()).decode()
            payload["fileName"] = label
        else:
            payload["file"] = label
        # A minute of audio plus a server round trip does not fit the 12s default.
        response = client.request("POST", "/transcribe", payload, timeout=90)
        check(isinstance(response, dict), "Transcribe response is not an object")
        transcript = response.get("transcript", "")
        check(transcript.strip(), "Clip %s produced no transcript" % label)
        echoed = {s.strip() for s in response.get("contextualStrings", [])}
        # The device trims, dedupes and caps, so compare as sets rather than
        # sequences; a dropped field is the failure this catches.
        check(echoed == requested,
              "Clip %s was biased with %r, not the requested %r" % (label, echoed, requested))
        results.append({
            "file": response.get("file", label),
            "note": clip.get("note", ""),
            "reference": clip["reference"],
            "transcript": transcript,
            "character_error_rate": round(character_error_rate(clip["reference"], transcript), 4),
            "matched": normalize_text(clip["reference"]) == normalize_text(transcript),
        })

    (directory / "transcripts.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    return {
        "contextualStrings": contextual_strings,
        "results": results,
        "mean_character_error_rate": round(sum(r["character_error_rate"] for r in results) / len(results), 4),
        "exact_matches": sum(1 for r in results if r["matched"]),
        "clip_count": len(results),
    }


def run_save(client, evidence):
    session = client.request("POST", "/session", {})
    evidence["session"] = session
    evidence["before"] = client.request("GET", "/snapshot")
    check(evidence["before"]["persistence"]["count"] == 0, "Fixture is not empty")
    text = "自动化验证：阅读后的思考应被完整保存在本机。"
    action_id, result = client.action(text)
    evidence["action"] = result
    check(result["status"] == "completed", "Save action did not complete")
    after = client.request("GET", "/snapshot")
    evidence["after"] = after
    check(after["runID"] == session["runID"], "Test session changed")
    check(after["model"]["state"] == "saved", "Model did not enter saved state")
    check(after["persistence"]["texts"] == [text], "Persisted text differs")
    check(after["persistence"]["reflectionIDs"] == [after["model"]["reflectionID"]], "Model/database identity mismatch")
    check(after["persistence"]["discussionCount"] == 1, "Discussion counter was not persisted")
    retry = client.request("POST", "/actions", {"id": action_id, "name": "reflection.submit", "text": text})
    check(retry == result, "Retry changed operation result")
    check(client.request("GET", "/snapshot")["persistence"]["count"] == 1, "Retry duplicated data")
    events = client.request("GET", "/events?after=0")
    evidence["save_events"] = events
    names = [e["name"] for e in events["events"] if e["actionID"] == action_id]
    check(names == ["action.started", "reflection.save.returned"], "Save event chain incomplete")
    # New isolated session proves blank-input rejection independently of saved-state guards.
    client.request("POST", "/session", {})
    _, rejected = client.action("   ")
    evidence["empty_action"] = rejected
    check(rejected["status"] == "rejected", "Empty input was accepted")
    empty = client.request("GET", "/snapshot")
    evidence["empty_snapshot"] = empty
    check(empty["persistence"]["count"] == 0, "Empty input wrote data")
    check(empty["model"]["state"] == "editing", "Rejected input changed model state")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["status", "perf", "save", "screenshot", "transcribe"])
    parser.add_argument("--base", default="http://127.0.0.1:18765")
    parser.add_argument("--output", type=Path, default=Path("/tmp/readloop-debug-runs"))
    parser.add_argument("--udid", help="Device to use when creating a new USB forward")
    parser.add_argument("--wait", type=float, default=15, help="Startup retry window in seconds")
    parser.add_argument("--scale", type=int, choices=[1, 2, 3], default=2,
                        help="Screenshot scale: 1 is point geometry, 3 is device pixels")
    parser.add_argument("--reference", type=Path,
                        help="transcribe: JSON manifest of clip file names and their spoken reference text")
    parser.add_argument("--contextual-strings", default="",
                        help="transcribe: comma-separated phrases to bias recognition toward")
    args = parser.parse_args()
    if args.command == "transcribe" and not args.reference:
        parser.exit(2, "transcribe needs --reference <clips.json>\n")
    contextual_strings = [s.strip() for s in args.contextual_strings.split(",") if s.strip()]
    client = Client(args.base)
    try:
        if args.base.rstrip("/") == "http://127.0.0.1:18765":
            forward_usb(args.udid)
        wait_ready(client, args.wait)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, "Connection failed: " + str(error) + "\n")
    if args.command in ("status", "perf"):
        print(json.dumps(client.request("GET", "/" + args.command), ensure_ascii=False, indent=2))
        return
    directory = args.output / str(uuid.uuid4())
    directory.mkdir(parents=True)
    evidence = {}
    code = 0
    try:
        evidence["status"] = client.request("GET", "/status")
        check(evidence["status"]["protocolVersion"] == 1, "Unsupported protocol")
        if args.command == "save":
            run_save(client, evidence)
        elif args.command == "transcribe":
            evidence["transcription"] = run_transcribe(
                client, directory, args.reference, contextual_strings)
        else:
            evidence["screenshot"] = run_screenshot(client, directory, args.scale)
        evidence["verdict"] = "PASS"
    except Exception as error:
        evidence["verdict"] = "FAIL"
        evidence["error"] = str(error)
        code = 1
    finally:
        if args.command == "save":
            try:
                evidence["latest_events"] = client.request("GET", "/events?after=0")
            except Exception as error:
                evidence["collection_error"] = str(error)
        (directory / "result.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
        if args.command == "save":
            events = evidence.get("save_events", {}).get("events", []) + evidence.get("latest_events", {}).get("events", [])
            (directory / "events.jsonl").write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events))
    summary = evidence.get("transcription")
    if summary:
        # The comparison is the deliverable here, not the directory path.
        for result in summary["results"]:
            print("%s  CER %.3f  %s%s" % ("=" if result["matched"] else " ", result["character_error_rate"],
                                          result["file"], " (%s)" % result["note"] if result["note"] else ""))
            print("    ref: " + result["reference"])
            print("    got: " + result["transcript"])
        print("mean CER %.3f over %d clips, %d exact" % (summary["mean_character_error_rate"],
                                                         summary["clip_count"], summary["exact_matches"]))
        print("bias: " + (", ".join(summary["contextualStrings"]) or "(none)"))
    print(evidence["verdict"], evidence.get("screenshot", {}).get("path") or directory)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
