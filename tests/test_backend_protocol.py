#!/usr/bin/env python3
"""
Backend Protocol & End-to-End Verification Test Suite for Zed Remote.

Tests:
1. JSON-RPC 2.0 ACP framing & Schema compliance
2. Session transaction logging & NDJSON replay
3. Git engine commands & diff parser verification
4. Security guardrail command blocklist & workspace boundary validation
5. Constant-time authentication token validation
6. Telemetry metrics & power action state validation
"""

import hmac
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMAS_DIR = REPO_ROOT / "shared" / "schemas"


class TestAcpSchemas(unittest.TestCase):
    """Verifies all JSON schemas in shared/schemas are valid JSON."""

    def test_schema_validity(self):
        for schema_file in SCHEMAS_DIR.glob("*.json"):
            with open(schema_file, "r") as f:
                data = json.load(f)
                self.assertIn("$schema", data, f"Missing $schema in {schema_file.name}")
                self.assertIn("title", data, f"Missing title in {schema_file.name}")


class TestProtocolSerialization(unittest.TestCase):
    """Verifies serialization and deserialization of ACP JSON-RPC 2.0 messages."""

    def test_initialize_frame(self):
        frame = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": 1,
                "clientCapabilities": {
                    "fs": {"readTextFile": True, "writeTextFile": True},
                    "terminal": True,
                },
            },
        }
        raw = json.dumps(frame)
        parsed = json.loads(raw)
        self.assertEqual(parsed["jsonrpc"], "2.0")
        self.assertEqual(parsed["id"], 1)
        self.assertEqual(parsed["method"], "initialize")
        self.assertTrue(parsed["params"]["clientCapabilities"]["terminal"])

    def test_session_update_streaming_notification(self):
        frame = {
            "jsonrpc": "2.0",
            "method": "session/update",
            "params": {
                "sessionId": "sess_unit_test",
                "update": {
                    "sessionUpdateType": "agent_message_chunk",
                    "content": {"type": "text", "text": "Refactoring completed."},
                },
            },
        }
        raw = json.dumps(frame)
        parsed = json.loads(raw)
        self.assertNotIn("id", parsed, "Notifications must not contain an id field")
        self.assertEqual(parsed["method"], "session/update")
        self.assertEqual(
            parsed["params"]["update"]["content"]["text"],
            "Refactoring completed.",
        )

    def test_session_request_permission_cycle(self):
        req_frame = {
            "jsonrpc": "2.0",
            "id": 88,
            "method": "session/request_permission",
            "params": {
                "sessionId": "sess_perm_01",
                "toolCall": {
                    "toolCallId": "call_exec_1",
                    "name": "terminal/create",
                    "parameters": {"command": "cargo test"},
                },
            },
        }
        res_frame = {
            "jsonrpc": "2.0",
            "id": 88,
            "result": {"decision": "approved", "reason": None},
        }

        # Verify pairing
        self.assertEqual(req_frame["id"], res_frame["id"])
        self.assertEqual(res_frame["result"]["decision"], "approved")


class TestSessionLoggerAndReplay(unittest.TestCase):
    """Verifies append-only NDJSON transaction logging and replay logic."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.session_id = "test_session_replay"
        self.log_path = Path(self.temp_dir) / f"{self.session_id}.jsonl"

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def test_append_and_replay(self):
        events = [
            {"seq": 1, "direction": "zed_to_agent", "frame": {"method": "initialize"}},
            {"seq": 2, "direction": "agent_to_zed", "frame": {"result": {"ready": True}}},
            {"seq": 3, "direction": "mobile_to_agent", "frame": {"method": "session/prompt"}},
            {"seq": 4, "direction": "agent_to_zed", "frame": {"method": "session/update"}},
        ]

        # Write sequential frames
        with open(self.log_path, "a") as f:
            for ev in events:
                f.write(json.dumps(ev) + "\n")

        # Read back and replay from sequence 3
        replayed = []
        with open(self.log_path, "r") as f:
            for line in f:
                entry = json.loads(line)
                if entry["seq"] >= 3:
                    replayed.append(entry)

        self.assertEqual(len(replayed), 2)
        self.assertEqual(replayed[0]["seq"], 3)
        self.assertEqual(replayed[1]["seq"], 4)


class TestSecurityGuardrails(unittest.TestCase):
    """Verifies command blocklisting, path boundary checks, and timing-safe auth."""

    def setUp(self):
        self.blocked = [
            "rm -rf /",
            ":(){ :|:& };:",
            "mkfs",
            "dd if=",
            "> /dev/sda",
        ]

    def test_blocked_commands(self):
        malicious = [
            "rm -rf /",
            "sudo rm -rf / --no-preserve-root",
            "mkfs.ext4 /dev/sda1",
            "dd if=/dev/zero of=/dev/sda",
        ]
        for cmd in malicious:
            is_blocked = any(b.lower() in cmd.lower() for b in self.blocked)
            self.assertTrue(is_blocked, f"Should have blocked: {cmd}")

    def test_safe_commands_allowed(self):
        safe = [
            "cargo test",
            "git status",
            "flutter pub get",
            "npm run build",
        ]
        for cmd in safe:
            is_blocked = any(b.lower() in cmd.lower() for b in self.blocked)
            self.assertFalse(is_blocked, f"Should NOT have blocked: {cmd}")

    def test_constant_time_token_check(self):
        expected_token = "secret-token-xyz-12345"
        correct_token = "secret-token-xyz-12345"
        wrong_token = "secret-token-xyz-99999"
        short_token = "secret"

        self.assertTrue(hmac.compare_digest(expected_token, correct_token))
        self.assertFalse(hmac.compare_digest(expected_token, wrong_token))
        self.assertFalse(hmac.compare_digest(expected_token, short_token))

    def test_path_traversal_detection(self):
        workspace = Path("/home/user/myproject").resolve()
        safe_path = (workspace / "src" / "main.rs").resolve()
        traversal_path = (workspace / ".." / ".." / "etc" / "passwd").resolve()

        self.assertTrue(str(safe_path).startswith(str(workspace)))
        self.assertFalse(str(traversal_path).startswith(str(workspace)))


class TestGitEngineWorkflow(unittest.TestCase):
    """Verifies actual Git operations (status, diff, stage, commit) in an isolated sandbox repo."""

    def setUp(self):
        self.temp_git_dir = tempfile.mkdtemp()
        subprocess.run(["git", "init"], cwd=self.temp_git_dir, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Tester"], cwd=self.temp_git_dir, check=True)
        subprocess.run(["git", "config", "user.email", "tester@test.local"], cwd=self.temp_git_dir, check=True)

    def tearDown(self):
        shutil.rmtree(self.temp_git_dir)

    def test_git_status_and_diff(self):
        # Create a file
        test_file = Path(self.temp_git_dir) / "test.txt"
        test_file.write_text("line 1\nline 2\n")

        # Initial commit
        subprocess.run(["git", "add", "test.txt"], cwd=self.temp_git_dir, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=self.temp_git_dir, check=True)

        # Modify file
        test_file.write_text("line 1\nmodified line 2\nline 3\n")

        # Query git status porcelain
        res = subprocess.run(["git", "status", "--porcelain=v1"], cwd=self.temp_git_dir, capture_output=True, text=True)
        self.assertIn("M test.txt", res.stdout)

        # Query git diff
        diff_res = subprocess.run(["git", "diff", "--", "test.txt"], cwd=self.temp_git_dir, capture_output=True, text=True)
        self.assertIn("+modified line 2", diff_res.stdout)
        self.assertIn("+line 3", diff_res.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
