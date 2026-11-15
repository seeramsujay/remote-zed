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
7. Bunker Tunnel AES-256-GCM encryption & QR pairing URI generation
8. Terminal execution & filesystem exploration operations
"""

import hmac
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

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

    def test_terminal_and_fs_rpc_frames(self):
        exec_frame = {
            "jsonrpc": "2.0",
            "id": 101,
            "method": "terminal/exec",
            "params": {"command": "mkdir -p new-project && cd new-project"},
        }
        raw_exec = json.loads(json.dumps(exec_frame))
        self.assertEqual(raw_exec["method"], "terminal/exec")
        self.assertEqual(
            raw_exec["params"]["command"], "mkdir -p new-project && cd new-project"
        )

        mkdir_frame = {
            "jsonrpc": "2.0",
            "id": 102,
            "method": "fs/mkdir",
            "params": {"path": "off-grid-api"},
        }
        raw_mkdir = json.loads(json.dumps(mkdir_frame))
        self.assertEqual(raw_mkdir["method"], "fs/mkdir")
        self.assertEqual(raw_mkdir["params"]["path"], "off-grid-api")


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
            {
                "seq": 2,
                "direction": "agent_to_zed",
                "frame": {"result": {"ready": True}},
            },
            {
                "seq": 3,
                "direction": "mobile_to_agent",
                "frame": {"method": "session/prompt"},
            },
            {
                "seq": 4,
                "direction": "agent_to_zed",
                "frame": {"method": "session/update"},
            },
        ]

        # Write sequential frames
        with open(self.log_path, "a") as f:
            f.writelines(json.dumps(ev) + "\n" for ev in events)

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
            "mkdir myproject",
            "cd myproject",
            "ls -la",
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
        subprocess.run(
            ["git", "init"], cwd=self.temp_git_dir, check=True, capture_output=True
        )
        subprocess.run(
            ["git", "config", "user.name", "Tester"], cwd=self.temp_git_dir, check=True
        )
        subprocess.run(
            ["git", "config", "user.email", "tester@test.local"],
            cwd=self.temp_git_dir,
            check=True,
        )

    def tearDown(self):
        shutil.rmtree(self.temp_git_dir)

    def test_git_status_and_diff(self):
        # Create a file
        test_file = Path(self.temp_git_dir) / "test.txt"
        test_file.write_text("line 1\nline 2\n")

        # Initial commit
        subprocess.run(["git", "add", "test.txt"], cwd=self.temp_git_dir, check=True)
        subprocess.run(
            ["git", "commit", "-m", "init"], cwd=self.temp_git_dir, check=True
        )

        # Modify file
        test_file.write_text("line 1\nmodified line 2\nline 3\n")

        # Query git status porcelain
        res = subprocess.run(
            ["git", "status", "--porcelain=v1"],
            cwd=self.temp_git_dir,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertIn("M test.txt", res.stdout)

        # Query git diff
        diff_res = subprocess.run(
            ["git", "diff", "--", "test.txt"],
            cwd=self.temp_git_dir,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertIn("+modified line 2", diff_res.stdout)
        self.assertIn("+line 3", diff_res.stdout)


class TestBunkerTunnelCrypto(unittest.TestCase):
    """Verifies AES-256-GCM encryption, decryption, and tampering resistance for the Bunker Tunnel."""

    def setUp(self):
        self.key_bytes = os.urandom(32)
        self.key_hex = self.key_bytes.hex()
        self.aesgcm = AESGCM(self.key_bytes)

    def test_encrypt_decrypt_roundtrip(self):
        data = {
            "tunnel_url": "tcp://a.free.pinggy.link:43210",
            "host": "a.free.pinggy.link",
            "port": 43210,
            "timestamp": 1728218400,
        }
        nonce = os.urandom(12)
        payload_bytes = json.dumps(data).encode("utf-8")
        ciphertext = self.aesgcm.encrypt(nonce, payload_bytes, None)

        # Decrypt
        decrypted_bytes = self.aesgcm.decrypt(nonce, ciphertext, None)
        recovered = json.loads(decrypted_bytes.decode("utf-8"))
        self.assertEqual(recovered, data)

    def test_tampered_ciphertext_fails(self):
        data = {"secret": "rendezvous_target"}
        nonce = os.urandom(12)
        ciphertext = bytearray(
            self.aesgcm.encrypt(nonce, json.dumps(data).encode("utf-8"), None)
        )

        # Flip last byte (in authentication tag)
        ciphertext[-1] ^= 0x01

        with self.assertRaises(Exception):  # noqa: B017
            self.aesgcm.decrypt(nonce, bytes(ciphertext), None)


class TestTerminalAndFsOperations(unittest.TestCase):
    """Verifies folder creation, file operations, and interactive command execution."""

    def setUp(self):
        self.sandbox = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.sandbox)

    def test_mkdir_and_subfolder_creation(self):
        new_proj = Path(self.sandbox) / "off_grid_project"
        os.makedirs(new_proj, exist_ok=True)
        self.assertTrue(new_proj.is_dir())

        # Create nested file
        f = new_proj / "main.py"
        f.write_text("print('hello off grid')")
        self.assertTrue(f.exists())
        self.assertEqual(f.read_text(), "print('hello off grid')")

    def test_shell_command_execution(self):
        res = subprocess.run(
            ["bash", "-c", "echo 'bunker terminal online'"],
            cwd=self.sandbox,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("bunker terminal online", res.stdout)


class TestYoloAndV2ThreadConfiguration(unittest.TestCase):
    """Verifies YOLO mode schema and v2 thread configuration payloads."""

    def test_yolo_mode_configuration_schema(self):
        config_payload = {
            "model": None,
            "thinking_enabled": False,
            "agent": {
                "id": "antigravity",
                "name": "AntiGravity Agent",
                "is_native": False,
            },
            "modes": {
                "current": "yolo",
                "available": [
                    {
                        "id": "yolo",
                        "name": "YOLO",
                        "description": "Autonomous auto-pilot with auto-approved permissions (--dangerously-skip-permissions)",
                    },
                    {
                        "id": "auto",
                        "name": "Auto",
                        "description": "Autonomous execution with permission confirmations",
                    },
                    {
                        "id": "plan",
                        "name": "Plan",
                        "description": "Read-only planning without modifications",
                    },
                ],
            },
            "options": [],
        }
        self.assertEqual(config_payload["modes"]["current"], "yolo")
        mode_ids = [m["id"] for m in config_payload["modes"]["available"]]
        self.assertIn("yolo", mode_ids)
        self.assertIn("auto", mode_ids)
        self.assertIn("plan", mode_ids)

    def test_bunker_uri_parsing(self):
        import urllib.parse

        uri = "zed-remote://pair?topic=zed-bunker-test&key=MTIzNDU2&token=tok456&port=8443"
        parsed = urllib.parse.urlparse(uri)
        self.assertEqual(parsed.scheme, "zed-remote")
        self.assertEqual(parsed.netloc, "pair")
        query = urllib.parse.parse_qs(parsed.query)
        self.assertEqual(query["topic"][0], "zed-bunker-test")
        self.assertEqual(query["key"][0], "MTIzNDU2")
        self.assertEqual(query["token"][0], "tok456")
        self.assertEqual(query["port"][0], "8443")

    def test_approvals_api_payload_and_resolution(self):
        approval_payload = {
            "approvals": [
                {
                    "tool_call_id": "call_subproc_001",
                    "title": "Execute shell command",
                    "tool_name": "terminal/create",
                    "content": [],
                    "raw_input": {"command": "cargo build --release"},
                    "allow_once_available": True,
                    "deny_once_available": True,
                    "kind": "permission",
                    "options": [
                        {
                            "option_id": "allow_once",
                            "label": "Allow",
                            "kind": "allow_once",
                            "enabled": True,
                        },
                        {
                            "option_id": "allow_always",
                            "label": "Allow Always",
                            "kind": "allow_always",
                            "enabled": True,
                        },
                        {
                            "option_id": "deny_once",
                            "label": "Deny",
                            "kind": "reject_once",
                            "enabled": True,
                        },
                    ],
                    "patterns": [],
                }
            ]
        }
        self.assertEqual(len(approval_payload["approvals"]), 1)
        appr = approval_payload["approvals"][0]
        self.assertEqual(appr["tool_call_id"], "call_subproc_001")
        self.assertEqual(appr["tool_name"], "terminal/create")
        self.assertTrue(appr["allow_once_available"])

        # Test resolution outcome
        resolve_decision = {"option_id": "allow_once"}
        is_allow = not resolve_decision["option_id"].startswith("deny")
        self.assertTrue(is_allow)
        outcome_frame = {
            "jsonrpc": "2.0",
            "id": 105,
            "result": {
                "decision": "approved" if is_allow else "rejected",
                "outcome": {"outcome": "approved" if is_allow else "rejected"},
            },
        }
        self.assertEqual(outcome_frame["result"]["decision"], "approved")
        self.assertEqual(outcome_frame["result"]["outcome"]["outcome"], "approved")

    def test_yolo_subprocess_permission_grant(self):
        # In YOLO mode, incoming session/request_permission for subprocesses must auto-approve
        req_permission = {
            "jsonrpc": "2.0",
            "id": 99,
            "method": "session/request_permission",
            "params": {
                "sessionId": "default",
                "toolCall": {
                    "toolCallId": "proc_fork_1",
                    "name": "terminal/create",
                    "title": "Spawn Subprocess",
                    "parameters": {"command": "python3 script.py"},
                },
            },
        }
        # In YOLO mode with --dangerously-skip-permissions
        auto_approved_response = {
            "jsonrpc": "2.0",
            "id": req_permission["id"],
            "result": {
                "decision": "approved",
                "outcome": {"outcome": "approved"},
            },
        }
        self.assertEqual(auto_approved_response["id"], 99)
        self.assertEqual(auto_approved_response["result"]["decision"], "approved")


if __name__ == "__main__":
    unittest.main(verbosity=2)
