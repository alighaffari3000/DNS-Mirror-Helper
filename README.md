# dns-mirror-helper

A bash utility for Ubuntu systems to manage DNS settings and apt mirror selection from a single interactive menu.

---

## Features

### DNS Manager
- **FREE mode** — routes DNS through [dnscrypt-proxy](https://github.com/DNSCrypt/dnscrypt-proxy) over DoH (DNS over HTTPS), bypassing local DNS restrictions
- **MELLI mode** — auto-tests a built-in list of DNS servers and applies the fastest working ones directly
- **Auto mode** — tries FREE mode first; falls back to MELLI automatically if international connectivity is unavailable
- **Manual DNS entry** — enter any custom DNS addresses (comma-separated); validates each IP before applying
- **Safe reset** — restarts DNS services and flushes caches
- **Connectivity tests** — checks DNS resolution and HTTPS reachability

### Mirror Manager
- Tests Iran and/or international Ubuntu mirrors for speed and latency
- Displays ranked results and gives you **10 seconds** to pick manually — auto-selects the best one on timeout or bare Enter
- Supports both legacy `sources.list` and modern DEB822 `ubuntu.sources` formats
- Automatically backs up your current sources file before any change
- **Backup manager** — list, inspect, and restore any previous sources backup

---

## Requirements

- Ubuntu (tested on 20.04, 22.04, 24.04)
- `bash` 4.3+
- `curl`, `dig` (dnsutils), `systemd-resolved`
- Root / sudo access
- `dnscrypt-proxy` — installed automatically if missing (via apt or GitHub binary)

---

## Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alighaffari3000/DNS-Mirror-Helper/main/dns-mirror-helper.sh)
```


---

## Usage

Run the script with sudo and navigate the interactive menu:

```
  DNS & Mirror Helper
=====================================
  1) DNS Manager
  2) Mirror Manager
  0) Exit
```

### DNS Manager

```
  1) Switch to FREE mode (DoH)
  2) Switch to MELLI mode (Auto DNS select)
  3) Auto-select best mode
  4) Manual DNS entry
  5) Safe reset DNS services
  6) Run connectivity tests
  0) Back
```

**Manual DNS entry example:**
```
DNS addresses: 1.1.1.1, 8.8.8.8, 9.9.9.9
[VALID] 1.1.1.1
[VALID] 8.8.8.8
[VALID] 9.9.9.9
```

### Mirror Manager

```
  1) Iran mirrors only
  2) International mirrors only
  3) Iran + International
  4) Manage backups
  0) Back
```

After selecting a mirror source, the script tests all candidates and shows ranked results:

```
Results (sorted by speed/latency):
  1) https://mirror.arvancloud.ir/ubuntu
     Latency: 11ms | Speed: 9200 KB/s | Score: 17
  2) https://ir.ubuntu.sindad.cloud/ubuntu
     Latency: 18ms | Speed: 7100 KB/s | Score: 27
  ...

Auto-selecting in 10s (or enter number + Enter):
```

Press a number to override, press Enter to confirm auto-selection, or wait 10 seconds.

---

## How DNS modes work

| Mode | Method | Use when |
|------|--------|----------|
| FREE | dnscrypt-proxy → DoH (Cloudflare, Google, Quad9) | International access is available |
| MELLI | Direct DNS from built-in list | DoH is blocked or unavailable |
| Manual | Your custom DNS addresses | You know exactly which DNS to use |
| Auto | Tries FREE, falls back to MELLI | Unsure which mode works |

---

## Configuration

### Adding or removing DNS servers (MELLI mode)

Edit the `IR_DNS_LIST` array near the top of the script.

### Adding or removing mirrors

Edit the `IR_MIRRORS` or `GLOBAL_MIRRORS` arrays. Lines starting with `#` are treated as comments and skipped.

### dnscrypt-proxy config

The script writes its own config to `/etc/dnscrypt-proxy/dnscrypt-proxy.toml`, listening on `127.0.0.1:5053` and using Cloudflare, Google, and Quad9 DoH resolvers. Edit `write_default_config()` in the script to customize.

---

## Restoring a backup

Every time a mirror is changed, the previous sources file is backed up automatically. To restore manually:

```bash
sudo cp /etc/apt/sources.list.bak.2024-01-15-143022 /etc/apt/sources.list
sudo apt update
```

Or use **Mirror Manager → Manage backups** from the interactive menu.

---

## Files modified by this script

| Path | Purpose |
|------|---------|
| `/etc/systemd/resolved.conf.d/dns-mirror-helper.conf` | systemd-resolved DNS config |
| `/etc/resolv.conf` | symlinked to the appropriate resolved stub |
| `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` | dnscrypt-proxy config (overwritten on each FREE mode activation) |
| `/etc/apt/sources.list` or `/etc/apt/sources.list.d/ubuntu.sources` | apt mirror config |
| `/etc/apt/sources.list.bak.*` | automatic backups |

---

## License

MIT
