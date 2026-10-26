# NetSleuth

NetSleuth is a Linux network diagnostics toolkit built with Bash and Python. It checks the local IPv4 default route, system DNS resolution, ICMP reachability, TCP connectivity, HTTP response status/latency, and TLS certificate validity. It also calculates IPv4 subnet details and can emit JSON reports.

## Requirements

- Linux (tested target: Kali/Debian-family distributions)
- Bash 4+
- Python 3
- `readlink`, `ip`, `ping`, `curl`, `timeout`, and `getent`
- Optional: `dig` for a direct public-resolver comparison
- `ss` is optional and used only to summarize local listening ports

On Kali/Debian, install common dependencies with:

```bash
sudo apt update
sudo apt install -y bash coreutils python3 iproute2 iputils-ping curl dnsutils
```

## Run without installing

```bash
chmod +x bin/sleuth libexec/tls_inspector.py
./bin/sleuth --help
./bin/sleuth example.com
./bin/sleuth https://example.com
./bin/sleuth -c 192.168.1.50/24
./bin/sleuth --json https://example.com
./bin/sleuth https://example.com:8443/health --save-report
```

Targets must be hostnames, IPv4 addresses, or HTTP(S) URLs. For conventional web ports, NetSleuth aligns the scheme with the selected port: 80/8080 use HTTP, while 443/8443 use HTTPS. A port override must be in the range 1–65535; leading zeroes are normalized. CIDR mode requires an IPv4 address/prefix such as `192.168.1.50/24`; IPv6 is not supported. Only test systems you own or have permission to assess. The tool sends ordinary DNS, ICMP, TCP, HTTP, and TLS probes; it is not a port scanner.

## Install command

```bash
./install.sh
```

The installer links `sleuth` into `/usr/local/bin` when run as root, or `~/.local/bin` for a regular user. The command resolves its real script location when invoked through the installed symlink so it can locate the TLS helper and save reports in the project directory. If the latter isn't in your PATH, add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile and open a new terminal.

## Reports and JSON

- `--json` emits one valid JSON document to stdout. Diagnostics are captured for a text report but do not pollute JSON output.
- `--save-report` saves a timestamped **text report** under `reports/`, including when `--json` is also supplied.
- JSON fields use stable types: booleans or `null` for reachability/resolution checks, an integer or `null` for `http_code`, a number or `null` for `http_time_seconds`, and `null` for unavailable optional values.
- CIDR mode also supports `--json`.

## Tests

```bash
bash tests/test_sleuth.sh
```

The tests cover argument validation, invalid IPv4/CIDR inputs, port normalization and scheme selection, symlinked TLS-helper discovery, CIDR text/JSON output, JSON field types, text report saving, and installer dependency checks. Probe commands are stubbed in the test suite where possible so tests don't depend on external network access.

## Design notes

- Certificate verification is enabled by default; the HTTP probe does not disable TLS verification.
- A failed ping is not treated as proof that a host is down.
- TCP checks classify connection attempts in one bounded Python call. A DNS lookup failure is distinct from a connection timeout or refusal.
- A default route without an explicit `via` address is reported as an interface route, which is common with VPN and point-to-point interfaces.
- Public DNS comparison is optional and may fail on networks that block direct DNS queries.

## Limitations

This is a learning/portfolio tool, not a production monitoring platform. IPv6 targets and IPv6 CIDR calculations are not supported. Gateway ICMP responses may be blocked. A timeout or refused connection alone cannot reliably identify the root cause.
