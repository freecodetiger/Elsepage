#!/usr/bin/env python3
"""Bounded, read-only snapshot through the command returned by device_open.

The caller must open the app with that same device-bound command first.
This wrapper does not discover devices, take over sessions, or retry failures.
"""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys


def positive_number(value):
    number = float(value)
    if not 0 < number < float("inf"):
        raise argparse.ArgumentTypeError("must be a finite positive number")
    return number


def positive_integer(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-device", required=True,
                        help="Exact executable returned by this thread's device_open")
    parser.add_argument("--timeout-ms", type=positive_integer, default=15000)
    parser.add_argument("--startup-timeout-ms", type=positive_integer, default=10000)
    parser.add_argument("--wall-timeout-seconds", type=positive_number, default=30)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    executable = Path(args.agent_device).expanduser()
    if not executable.is_absolute():
        parser.error("use the absolute executable path returned by device_open")
    if not executable.is_file() or not os.access(executable, os.X_OK):
        parser.error("device command is missing; obtain a fresh command with device_open")

    command = [str(executable), "snapshot", "-i", "--timeout", str(args.timeout_ms)]
    if args.debug:
        command.append("--debug")
    environment = os.environ.copy()
    environment["AGENT_DEVICE_DAEMON_STARTUP_TIMEOUT_MS"] = str(args.startup_timeout_ms)
    process = subprocess.Popen(command, env=environment, start_new_session=True)
    try:
        result = process.wait(timeout=args.wall_timeout_seconds)
        return result if result >= 0 else 128 - result
    except subprocess.TimeoutExpired:
        # Stop only this invocation's local process group. The shared device
        # daemon and any other session must remain under their tool owner.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        # The parent can exit while a child ignores SIGTERM; finish the group.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        print(
            "Device snapshot caller deadline exceeded; local CLI stopped (exit 124). "
            "Remote request cancellation is not verified. No automatic retry.",
            file=sys.stderr,
        )
        return 124


if __name__ == "__main__":
    sys.exit(main())
