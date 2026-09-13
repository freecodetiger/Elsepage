#!/usr/bin/env python3
"""ReadLoop DEBUG USB client: automatically establishes forwarding, no token required."""
import argparse
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

    def request(self, method, path, payload=None):
        data = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(self.base + path, data=data, method=method,
            headers={"Content-Type": "application/json"})
        with self.opener.open(request, timeout=12) as response:
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
    parser.add_argument("command", choices=["status", "perf", "save"])
    parser.add_argument("--base", default="http://127.0.0.1:18765")
    parser.add_argument("--output", type=Path, default=Path("/tmp/readloop-debug-runs"))
    parser.add_argument("--udid", help="Device to use when creating a new USB forward")
    parser.add_argument("--wait", type=float, default=15, help="Startup retry window in seconds")
    args = parser.parse_args()
    client = Client(args.base)
    try:
        if args.base.rstrip("/") == "http://127.0.0.1:18765":
            forward_usb(args.udid)
        wait_ready(client, args.wait)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, "Connection failed: " + str(error) + "\n")
    if args.command != "save":
        print(json.dumps(client.request("GET", "/" + args.command), ensure_ascii=False, indent=2))
        return
    directory = args.output / str(uuid.uuid4())
    directory.mkdir(parents=True)
    evidence = {}
    code = 0
    try:
        evidence["status"] = client.request("GET", "/status")
        check(evidence["status"]["protocolVersion"] == 1, "Unsupported protocol")
        run_save(client, evidence)
        evidence["verdict"] = "PASS"
    except Exception as error:
        evidence["verdict"] = "FAIL"
        evidence["error"] = str(error)
        code = 1
    finally:
        try:
            evidence["latest_events"] = client.request("GET", "/events?after=0")
        except Exception as error:
            evidence["collection_error"] = str(error)
        (directory / "result.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
        events = evidence.get("save_events", {}).get("events", []) + evidence.get("latest_events", {}).get("events", [])
        (directory / "events.jsonl").write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events))
    print(evidence["verdict"], directory)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
