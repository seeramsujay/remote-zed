#!/usr/bin/env python3
"""
Bunker Tunnel: Firewall-Resistant, Zero-Trust Reverse Tunnel with QR Pairing.

Bypasses enterprise deep packet inspection (Fortinet, Palo Alto) by tunneling
TCP over port 443 via Pinggy, encrypting dynamic rendezvous URLs with AES-256-GCM,
publishing to a secret ntfy topic, and printing a terminal QR code for instant mobile pairing.
"""

import argparse
import base64
import json
import os
import re
import secrets
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    print(
        "Error: 'cryptography' library is required. Install with: pip install cryptography",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    import qrcode
    from qrcode import constants as qr_constants
except ImportError:
    qrcode = None
    qr_constants = None

CONFIG_DIR = Path.home() / ".zed-remote"
CONFIG_FILE = CONFIG_DIR / "bunker.json"


def generate_bunker_keys():
    """Generates a 256-bit AES-GCM key, random topic, and daemon token."""
    bunker_key = secrets.token_hex(32)  # 256-bit key
    topic = f"zed-bunker-{secrets.token_hex(6)}"
    daemon_token = secrets.token_hex(32)
    return {
        "bunker_key": bunker_key,
        "ntfy_topic": topic,
        "daemon_token": daemon_token,
        "local_port": 8443,
        "created_at": int(time.time()),
    }


def save_config(config):
    """Saves bunker configuration to ~/.zed-remote/bunker.json."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    os.chmod(CONFIG_FILE, 0o600)
    print(f"[*] Configuration saved to {CONFIG_FILE} (permissions: 0600)")


def load_config():
    """Loads existing configuration from disk or exits."""
    if not CONFIG_FILE.exists():
        print(
            f"[-] No configuration found at {CONFIG_FILE}. Run 'bunker_tunnel.py pair' first.",
            file=sys.stderr,
        )
        sys.exit(1)
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)


def encrypt_payload(key_hex: str, data: dict) -> str:
    """Encrypts a dictionary with AES-256-GCM using a 256-bit hex key."""
    key = bytes.fromhex(key_hex)
    aesgcm = AESGCM(key)
    nonce = secrets.token_bytes(12)  # 96-bit nonce for GCM
    payload_bytes = json.dumps(data).encode("utf-8")
    ciphertext = aesgcm.encrypt(nonce, payload_bytes, None)

    # Pack nonce + ciphertext (which includes 16-byte authentication tag)
    encrypted_blob = nonce + ciphertext
    return base64.urlsafe_b64encode(encrypted_blob).decode("ascii")


def decrypt_payload(key_hex: str, b64_ciphertext: str) -> dict:
    """Decrypts a base64-encoded AES-256-GCM blob back into a dictionary."""
    key = bytes.fromhex(key_hex)
    aesgcm = AESGCM(key)
    raw_blob = base64.urlsafe_b64decode(b64_ciphertext.encode("ascii"))
    nonce = raw_blob[:12]
    ciphertext = raw_blob[12:]
    decrypted_bytes = aesgcm.decrypt(nonce, ciphertext, None)
    return json.loads(decrypted_bytes.decode("utf-8"))


def render_terminal_qr(pairing_uri: str):
    """Renders an ASCII QR code directly into the terminal."""
    if qrcode is None or qr_constants is None:
        print(
            "\n[!] Python 'qrcode' module not installed. Install with: pip install qrcode"
        )
        print(f"[!] Pairing URI: {pairing_uri}\n")
        return

    qr = qrcode.QRCode(
        version=1,
        error_correction=qr_constants.ERROR_CORRECT_L,
        box_size=1,
        border=2,
    )
    qr.add_data(pairing_uri)
    qr.make(fit=True)

    print("\n" + "=" * 60)
    print("   SCAN THIS QR CODE IN ZED REMOTE MOBILE APP")
    print("=" * 60 + "\n")
    qr.print_ascii(invert=True)
    print("=" * 60)
    print(f"Pairing URI:\n{pairing_uri}")
    print("=" * 60 + "\n")


def get_local_ip() -> str:
    """Discovers host LAN IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def cmd_pair(args):
    """Generates credentials and displays dual-engine pairing options."""
    config = generate_bunker_keys()
    if args.port:
        config["local_port"] = args.port
    if args.topic:
        config["ntfy_topic"] = args.topic

    save_config(config)

    pairing_uri = (
        f"zed-remote://pair?"
        f"topic={config['ntfy_topic']}&"
        f"key={config['bunker_key']}&"
        f"token={config['daemon_token']}&"
        f"port={config['local_port']}"
    )

    local_ip = get_local_ip()
    web_bridge_url = f"http://{local_ip}:{config['local_port']}/?token={config['daemon_token']}"

    print("\n" + "=" * 60)
    print("   [METHOD 1 - Primary] NATIVE ANDROID COMPANION APP")
    print("=" * 60)
    render_terminal_qr(pairing_uri)
    print(f"Pairing URI: {pairing_uri}\n")

    print("=" * 60)
    print("   [METHOD 2 - Fallback] OPENCODE MOBILE WEB BRIDGE (PWA)")
    print("=" * 60)
    print("Open directly in ANY mobile browser (Chrome/Safari) or install as PWA:")
    print(f"URL: {web_bridge_url}\n")
    render_terminal_qr(web_bridge_url)

    print("[+] Pairing parameters generated successfully.")
    print(f"    - Ntfy Topic:       {config['ntfy_topic']}")
    print(
        f"    - AES-256 Key:      {config['bunker_key'][:8]}...{config['bunker_key'][-8:]}"
    )
    print(
        f"    - Daemon Token:     {config['daemon_token'][:8]}...{config['daemon_token'][-8:]}"
    )
    print(f"    - Local Daemon Port:{config['local_port']}")
    print(f"    - Web Bridge URL:   {web_bridge_url}\n")
    print("[*] To start the bunker tunnel service, run:")
    print("    python3 daemon/scripts/bunker_tunnel.py run\n")


def publish_to_ntfy(topic: str, ciphertext: str) -> bool:
    """Publishes encrypted ciphertext to ntfy.sh topic."""
    url = f"https://ntfy.sh/{topic}"
    try:
        req = subprocess.run(
            [
                "curl",
                "-s",
                "-X",
                "POST",
                "-H",
                "Title: Zed Remote Tunnel Active",
                "-H",
                "Priority: default",
                "-H",
                "Tags: lock,shield",
                "-d",
                ciphertext,
                url,
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        return req.returncode == 0
    except Exception as e:
        print(f"[-] Error publishing to ntfy: {e}", file=sys.stderr)
        return False


def cmd_run(args):
    """Runs the persistent Pinggy reverse tunnel and encrypted ntfy publishing loop."""
    config = load_config()
    topic = config["ntfy_topic"]
    key_hex = config["bunker_key"]
    local_port = config.get("local_port", 8443)

    print("\n" + "=" * 60)
    print("   STARTING BUNKER TUNNEL (FORTINET / FIREWALL RESISTANT)")
    print("=" * 60)
    print(f"[*] Local Daemon Target:  localhost:{local_port}")
    print("[*] Egress Protocol:      SSH over TCP Port 443 (free.pinggy.io)")
    print(f"[*] Rendezvous Channel:   https://ntfy.sh/{topic} (AES-256-GCM Encrypted)")
    print("=" * 60 + "\n")

    log_file = CONFIG_DIR / "pinggy.log"

    def cleanup(signum, frame):
        print("\n[*] Stopping tunnel supervisor...")
        subprocess.run(["pkill", "-f", "free.pinggy.io"], capture_output=True)
        sys.exit(0)

    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    rotation_interval_seconds = 3300  # 55 minutes

    while True:
        print(
            f"[{time.strftime('%X')}] Initializing fresh reverse tunnel via Pinggy port 443..."
        )
        subprocess.run(["pkill", "-f", "free.pinggy.io"], capture_output=True)

        ssh_cmd = [
            "ssh",
            "-p",
            "443",
            f"-R0:localhost:{local_port}",
            "tcp@free.pinggy.io",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "ServerAliveInterval=30",
            "-o",
            "ServerAliveCountMax=3",
            "-o",
            "ConnectTimeout=10",
        ]

        with open(log_file, "w") as out_f:
            proc = subprocess.Popen(ssh_cmd, stdout=out_f, stderr=subprocess.STDOUT)

        # Give handshake time to finish
        tunnel_url = None
        for attempt in range(12):
            time.sleep(1)
            if log_file.exists():
                content = log_file.read_text()
                match = re.search(r"tcp://([a-zA-Z0-9.-]+:[0-9]+)", content)
                if match:
                    tunnel_url = match.group(0)
                    break

        if tunnel_url:
            print(f"[+] Tunnel live: {tunnel_url}")

            # Parse host and port
            clean_addr = tunnel_url.replace("tcp://", "")
            host, port_str = clean_addr.split(":")

            payload = {
                "tunnel_url": tunnel_url,
                "host": host,
                "port": int(port_str),
                "timestamp": int(time.time()),
                "expires_in": rotation_interval_seconds,
            }

            # Encrypt with AES-256-GCM
            ciphertext = encrypt_payload(key_hex, payload)
            print(f"[*] Payload encrypted with AES-256-GCM ({len(ciphertext)} bytes)")

            # Publish to ntfy
            if publish_to_ntfy(topic, ciphertext):
                print(
                    f"[+] Published encrypted rendezvous update to https://ntfy.sh/{topic}"
                )
            else:
                print("[-] Warning: Failed to publish rendezvous to ntfy.")
        else:
            print("[-] Could not capture tunnel URL from Pinggy within timeout.")

        print(
            f"[*] Sleeping for 55 minutes (next rotation at {time.strftime('%X', time.localtime(time.time() + rotation_interval_seconds))})..."
        )
        try:
            time.sleep(rotation_interval_seconds)
        except KeyboardInterrupt:
            if proc.poll() is None:
                proc.terminate()
            break
        finally:
            if proc.poll() is None:
                proc.terminate()


def cmd_test_crypto(args):
    """Verifies AES-256-GCM encryption and decryption roundtrip."""
    config = generate_bunker_keys()
    test_data = {
        "tunnel_url": "tcp://a.free.pinggy.link:43210",
        "timestamp": 1728218400,
    }
    ciphertext = encrypt_payload(config["bunker_key"], test_data)
    recovered = decrypt_payload(config["bunker_key"], ciphertext)

    assert recovered == test_data, "Decryption mismatch!"
    print("[+] AES-256-GCM encrypt/decrypt test PASSED:")
    print(f"    Plaintext:  {test_data}")
    print(f"    Ciphertext: {ciphertext[:32]}... ({len(ciphertext)} chars)")
    print(f"    Recovered:  {recovered}")


def main():
    parser = argparse.ArgumentParser(
        description="Bunker Tunnel: Firewall-Resistant Zero-Trust Tunnel for Zed Remote"
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # pair
    p_pair = subparsers.add_parser(
        "pair", help="Generate credentials and show QR code for phone"
    )
    p_pair.add_argument(
        "--port", type=int, default=8443, help="Local daemon port (default: 8443)"
    )
    p_pair.add_argument("--topic", type=str, help="Custom ntfy topic name")
    p_pair.set_defaults(func=cmd_pair)

    # run
    p_run = subparsers.add_parser(
        "run", help="Start the Pinggy reverse tunnel and encrypted ntfy publisher loop"
    )
    p_run.set_defaults(func=cmd_run)

    # test
    p_test = subparsers.add_parser(
        "test-crypto", help="Test AES-256-GCM encryption roundtrip"
    )
    p_test.set_defaults(func=cmd_test_crypto)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
