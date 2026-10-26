#!/usr/bin/env python3
"""Verify a remote TLS certificate and return structured JSON."""
import json, socket, ssl, sys
from datetime import datetime, timezone

def inspect_tls(host: str, port: int = 443, timeout: float = 3.0) -> dict:
    result = {"connected": False, "tls_version": None, "cipher": None,
              "issuer": {}, "subject": {}, "sans": [], "days_left": None,
              "is_expired": None, "error": None}
    context = ssl.create_default_context()  # Certificate and hostname verification enabled.
    try:
        with socket.create_connection((host, port), timeout=timeout) as raw:
            with context.wrap_socket(raw, server_hostname=host) as sock:
                result["connected"] = True
                result["tls_version"] = sock.version()
                cipher = sock.cipher()
                result["cipher"] = cipher[0] if cipher else None
                cert = sock.getpeercert()
                for group in cert.get("issuer", ()):
                    for key, value in group: result["issuer"][key] = value
                for group in cert.get("subject", ()):
                    for key, value in group: result["subject"][key] = value
                result["sans"] = [value for kind, value in cert.get("subjectAltName", ()) if kind == "DNS"]
                expiry = cert.get("notAfter")
                if expiry:
                    dt = datetime.strptime(expiry, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
                    seconds = (dt - datetime.now(timezone.utc)).total_seconds()
                    result["days_left"] = int(seconds // 86400)
                    result["is_expired"] = seconds <= 0
    except ssl.SSLCertVerificationError as exc:
        result["error"] = f"Certificate verification failed: {exc.verify_message}"
    except socket.timeout:
        result["error"] = "Connection timed out during TLS handshake"
    except ConnectionRefusedError:
        result["error"] = "Connection refused"
    except OSError as exc:
        result["error"] = f"Network error: {exc}"
    except Exception as exc:  # Keep CLI output valid JSON for unexpected failures.
        result["error"] = f"TLS inspection error: {type(exc).__name__}: {exc}"
    return result

if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        print(json.dumps({"error": "Usage: tls_inspector.py HOSTNAME [PORT]"})); sys.exit(2)
    try: port = int(sys.argv[2]) if len(sys.argv) == 3 else 443
    except ValueError:
        print(json.dumps({"error": "Port must be an integer"})); sys.exit(2)
    if not 1 <= port <= 65535:
        print(json.dumps({"error": "Port must be between 1 and 65535"})); sys.exit(2)
    result = inspect_tls(sys.argv[1], port)
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["connected"] and not result["error"] and not result["is_expired"] else 1)
