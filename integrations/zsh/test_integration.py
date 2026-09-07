#!/usr/bin/env python3
"""Isolated subprocess/ZLE tests. Does not execute the text being transformed."""
import json
import os
from pathlib import Path
import pty
import select
import shlex
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HELPER = str(Path(sys.argv[1]).resolve())


def request(left, right="", session=None):
    result = subprocess.run([HELPER], input=json.dumps({"version": 1, "leftBuffer": left,
        "rightBuffer": right, "session": session}).encode(), capture_output=True, check=True, timeout=5)
    return json.loads(result.stdout)


def zle_case(left, right, repeats=1, helper=HELPER, interrupt_cycle=False):
    with tempfile.TemporaryDirectory(prefix="punto-zle-") as work:
        output = Path(work) / "buffers"
        pid, fd = pty.fork()
        if pid == 0:
            env = dict(os.environ, TERM="xterm-256color", LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8",
                       PUNTO_TEST_LEFT=left, PUNTO_TEST_RIGHT=right, PUNTO_TEST_OUTPUT=str(output),
                       FREEPUNTO_HELPER=helper, HISTFILE="/dev/null", PS1="PUNTO> ")
            os.execve("/bin/zsh", ["zsh", "-f", "-i"], env)
        try:
            setup = (
                "source " + shlex.quote(str(ROOT / "integrations/zsh/freepunto.zsh")) + "; "
                "_punto_seed() { LBUFFER=$PUNTO_TEST_LEFT; RBUFFER=$PUNTO_TEST_RIGHT; }; "
                "_punto_capture() { printf '%s\\0' \"$LBUFFER\" \"$RBUFFER\" > \"$PUNTO_TEST_OUTPUT\"; zle send-break; }; "
                "zle -N _punto_seed; zle -N _punto_capture; "
                "bindkey '^X^I' _punto_seed; bindkey '^X^P' freepunto-layout; bindkey '^X^O' _punto_capture; "
                "print -r -- PUNTO_READY\n"
            )
            os.write(fd, setup.encode())
            transcript = b""
            deadline = time.monotonic() + 5
            while (b"\r\nPUNTO_READY\r\n" not in transcript or
                   b"\x1b[?2004h" not in transcript.split(b"\r\nPUNTO_READY\r\n")[-1]):
                assert time.monotonic() < deadline, "zsh setup timeout"
                if select.select([fd], [], [], 0.1)[0]:
                    transcript += os.read(fd, 65536)
            keys = b"\x18\x09" + b"\x18\x10" * repeats
            if interrupt_cycle:
                # Another widget resets repeat state even if it leaves the buffer identical.
                keys += b"\x18\x09" + b"\x18\x10"
            os.write(fd, keys + b"\x18\x0f")
            deadline = time.monotonic() + 8
            while not output.exists() or not output.read_bytes().endswith(b"\0"):
                assert time.monotonic() < deadline, "ZLE capture timeout: " + repr(transcript[-1800:])
                if select.select([fd], [], [], 0.05)[0]:
                    transcript += os.read(fd, 65536)
            values = output.read_bytes().decode().split("\0")
            assert len(values) == 3
            return tuple(values[:2])
        finally:
            os.kill(pid, signal.SIGKILL)
            os.close(fd)
            os.waitpid(pid, 0)


first = request("echo ghbdtn \t\u00a0", " tail 😀")
assert first["leftBuffer"] == "echo привет \t\u00a0"
assert first["rightBuffer"] == " tail 😀"
state = None
left = "s"
for expected in ["ы", "і", "s", "ы", "і", "s"]:
    result = request(left, " right", state)
    left, state = result["leftBuffer"], result["session"]
    assert left == expected, (left, expected)
assert request("s", "changed", state)["leftBuffer"] == "ы"
for left in ["", " \t", "old word\n", "old word\n \t"]:
    assert request(left)["leftBuffer"] == left
assert request("😀 cafe\u0301 ghbdtn", "suffix")["leftBuffer"] == "😀 cafe\u0301 привет"
for bad in [b"not json", b'{"version":2,"leftBuffer":"s","rightBuffer":""}', b"x" * 1_048_577]:
    failed = subprocess.run([HELPER], input=bad, capture_output=True, timeout=5)
    assert failed.returncode != 0 and not failed.stdout

raw = "echo ghbdtn \t\u00a0\0 tail\0\0".encode()
bridge = subprocess.run([sys.executable, str(ROOT / "integrations/zsh/bridge.py"), HELPER],
                        input=raw, capture_output=True, timeout=5, check=True)
assert bridge.stdout.decode().split("\0")[0] == "echo привет \t\u00a0"
failed_bridge = subprocess.run([sys.executable, str(ROOT / "integrations/zsh/bridge.py"), "/nonexistent/punto"],
                               input=raw, capture_output=True, timeout=5)
assert failed_bridge.returncode != 0 and not failed_bridge.stdout
print("PASS: JSON helper and bridge, repeated cycles, invalid input, exact whitespace and right buffer")

assert zle_case("echo ghbdtn \t\u00a0", " tail 😀") == ("echo привет \t\u00a0", " tail 😀")
for repeats, expected in [(1, "ы"), (2, "і"), (3, "s"), (6, "s")]:
    assert zle_case("s", " right", repeats=repeats) == (expected, " right")
assert zle_case("old command\nghbdtn", " tail") == ("old command\nпривет", " tail")
assert zle_case("old word\n \t", "") == ("old word\n \t", "")
assert zle_case("s", "suffix", helper="/nonexistent/punto") == ("s", "suffix")
assert zle_case("s", "suffix", repeats=2, interrupt_cycle=True) == ("ы", "suffix")
with tempfile.TemporaryDirectory(prefix="punto-no-exec-") as work:
    marker = Path(work) / "must-not-exist"
    prefix = "$(touch " + shlex.quote(str(marker)) + "); "
    assert zle_case(prefix + "ghbdtn", "") == (prefix + "привет", "")
    assert not marker.exists(), "ZLE must never execute the edited command"
print("PASS: isolated zsh ZLE widget, 1/2/3/6 repeats, multiline, failure leaves buffer intact, cycle reset, no command execution")
