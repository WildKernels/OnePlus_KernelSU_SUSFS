#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
python3 - "$root" <<'PY'
import os
import pty
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time
import tty

root = sys.argv[1]
source = os.path.join(root, "nethunter/nfc/nci_raw_tool.c")

with tempfile.TemporaryDirectory(prefix="nci-tool-contract-") as tmp:
    master, slave = pty.openpty()
    tty.setraw(slave)
    device = os.ttyname(slave)
    tool = os.path.join(tmp, "nci_raw_tool")
    socket_path = os.path.join(tmp, "nci.sock")
    subprocess.run([
        "cc", "-Wall", "-Werror", f'-DNQ_NCI_DEV="{device}"',
        "-DNQ_NCI_SKIP_POWER",
        source, "-o", tool,
    ], check=True)
    os.close(slave)

    def run(*args):
        return subprocess.run([tool, *args], text=True, capture_output=True)

    invalid = run("unknown")
    assert invalid.returncode != 0, "invalid command accepted"
    assert "Usage:" in invalid.stderr, invalid.stderr

    probe = run("probe")
    assert probe.returncode == 0, f"probe failed: {probe.stderr}"

    odd_hex = run("send", "--socket", socket_path, "2000010")
    assert odd_hex.returncode != 0, "odd-length hex accepted"
    bad_hex = run("send", "--socket", socket_path, "20zz0100")
    assert bad_hex.returncode != 0, "non-hex characters accepted"
    bad_frame = run("send", "--socket", socket_path, "20000200")
    assert bad_frame.returncode != 0, "invalid NCI payload length accepted"

    def start_session():
        proc = subprocess.Popen([tool, "session", "--socket", socket_path],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise AssertionError(f"session exited early: {proc.stderr.read()}")
            if os.path.exists(socket_path):
                try:
                    probe_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    probe_sock.connect(socket_path)
                    probe_sock.close()
                    return proc
                except OSError:
                    pass
            time.sleep(0.01)
        proc.kill()
        raise AssertionError("session socket did not become ready")

    def stop_session(proc, client=None, expect_end=False):
        proc.send_signal(signal.SIGTERM)
        if client is not None:
            client.settimeout(3)
            trailer = client.recv(4096)
            if expect_end:
                assert b"END\n" in trailer, trailer
            else:
                assert trailer == b"", trailer
            client.close()
        assert proc.wait(timeout=3) == 0

    proc = start_session()
    second = run("session", "--socket", socket_path)
    assert second.returncode != 0, "second session owner accepted existing socket"

    capture_client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    capture_client.connect(socket_path)
    capture_client.sendall(b"CAPTURE 10\n")
    os.write(master, bytes([0x60, 0x00, 0x01, 0x42]))
    capture_client.settimeout(3)
    frame = capture_client.recv(4096)
    assert b"FRAME 60000142\n" in frame, frame
    stop_session(proc, capture_client, expect_end=True)

    proc = start_session()
    send_client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    send_client.connect(socket_path)
    send_client.sendall(b"SEND 20000100\n")
    readable, _, _ = select.select([master], [], [], 3)
    assert readable, "session did not write NCI command to device"
    sent = os.read(master, 16)
    assert sent == bytes([0x20, 0x00, 0x01, 0x00]), sent
    os.write(master, bytes([0x40, 0x00, 0x01, 0x00]))
    send_client.settimeout(3)
    response = send_client.recv(4096)
    assert b"OK 20000100 RESPONSE 40000100\n" in response, response
    stop_session(proc, send_client)

    os.close(master)

print("NCI tool contract tests passed")
PY
