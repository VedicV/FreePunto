#!/usr/bin/env python3
"""NUL-framed ZLE buffers <-> versioned JSON helper protocol. Never executes shell text."""
import json
import subprocess
import sys


def main():
    raw = sys.stdin.buffer.read(1_048_577)
    if len(raw) > 1_048_576:
        raise ValueError("input limit")
    fields = raw.decode("utf-8").split("\0")
    if len(fields) != 4 or fields[-1]:
        raise ValueError("framing")
    left, right, session_text = fields[:3]
    request = {"version": 1, "leftBuffer": left, "rightBuffer": right,
               "session": json.loads(session_text) if session_text else None}
    completed = subprocess.run([sys.argv[1]], input=json.dumps(request).encode("utf-8"),
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3, check=True)
    if len(completed.stdout) > 2_097_152:
        raise ValueError("output limit")
    response = json.loads(completed.stdout)
    new_left = response["leftBuffer"]
    if response["version"] != 1 or response["rightBuffer"] != right or not isinstance(new_left, str) or "\0" in new_left:
        raise ValueError("response")
    session = json.dumps(response.get("session"), ensure_ascii=True, separators=(",", ":"))
    sys.stdout.buffer.write((new_left + "\0" + session + "\0ok\0").encode("utf-8"))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, IndexError, OSError, subprocess.SubprocessError):
        # Do not echo the shell buffer, JSON, or helper stderr into terminal/logs.
        sys.exit(1)
