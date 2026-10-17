"""Exercise upstream hooks against a real isolated Unix socket, not log wording.

Python is the dependency under test and provides the socket receiver. Nothing
connects to Herdr or touches real agent configuration in this test.
"""
import json
import os
from pathlib import Path
import selectors
import socket
import subprocess
import sys
import tempfile

package, source, clean_path = sys.argv[1:]


def invoke(script, kind, root, payload, expect_report):
    endpoint = str(root / "receiver.sock")
    env = {"PATH": clean_path, "HOME": str(root), "TMPDIR": str(root),
           "HERDR_ENV": "1", "HERDR_SOCKET_PATH": endpoint,
           "HERDR_PANE_ID": "test:p1"}
    with socket.socket(socket.AF_UNIX) as listener:
        listener.bind(endpoint)
        listener.listen(1)
        process = subprocess.Popen(
            [clean_path.split(":")[0] + "/bash", str(script), "session"],
            env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE)
        process.stdin.write(json.dumps(payload).encode())
        process.stdin.close()
        process.stdin = None
        received = None
        if expect_report:
            with selectors.DefaultSelector() as selector:
                selector.register(listener, selectors.EVENT_READ)
                assert selector.select(5), f"{kind}: no socket report"
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(5)
                received = json.loads(conn.makefile("rb").readline())
                conn.sendall(b'{"result":{}}\n')
        stdout, stderr = process.communicate(timeout=5)
        assert process.returncode == 0, stderr
        assert stdout == b"" and stderr == b"", (stdout, stderr)
        if expect_report:
            assert received["method"] == "pane.report_agent_session"
            params = received["params"]
            assert params["agent"] == kind
            assert params["pane_id"] == env["HERDR_PANE_ID"]
            assert params["agent_session_id"] == payload["session_id"]
        else:
            with selectors.DefaultSelector() as selector:
                selector.register(listener, selectors.EVENT_READ)
                assert not selector.select(0), f"{kind}: unexpected report"
    os.unlink(endpoint)


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    for kind in ("claude", "codex", "grok"):
        event = "session_start" if kind == "grok" else "SessionStart"
        payload = {"hook_event_name": event, "session_id": "fixture-session",
                   "transcript_path": str(root / "transcript.jsonl"),
                   "source": "resume"}
        upstream = Path(source) / "src/integration/assets" / kind / "herdr-agent-state.sh"
        wrapped = Path(package) / "share/herdr-hooks" / (kind + ".sh")
        # Reproduce silent loss with the unmodified upstream script.
        invoke(upstream, kind, root, payload, False)
        invoke(wrapped, kind, root, payload, True)
        invoke(wrapped, kind, root, {**payload, "hook_event_name": "PostToolUse"}, False)
        invoke(wrapped, kind, root, {"hook_event_name": event}, False)
        print(f"PASS {kind}: original failure, real report, wrong event, missing ID")
    # The public output must expose no python executable. Its dependency is
    # referenced by hook scripts/wrappers, not merged into the user profile.
    assert not (Path(package) / "bin/python3").exists()
    assert sorted(p.name for p in (Path(package) / "bin").iterdir()) == ["collie-runtime"]
    print("PASS runtime exports only collie-runtime, not Python")
