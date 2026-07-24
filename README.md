# dns-mirror-helper

🇮🇷  [توضیحات فارسی](README_FA.md)

A bash utility for Ubuntu systems to manage DNS settings and apt mirror selection from a single interactive menu — with extra resilience for Internet blackouts.
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
- **Fast offline pre-check** — unreachable mirrors are dropped in seconds (a single reachability probe with a `HEAD` request, falling back to a ranged `GET` for mirrors that reject `HEAD`) before the slower speed tests run
- **Automatic international-outage detection** — when international links are down, the *Iran + International* scan skips the global pool automatically and the *International only* scan offers to switch to Iran mirrors
- **Last known-good mirror** — the mirror that last passed `apt update` is remembered and can be re-applied instantly, without a full scan
- Displays ranked results and gives you **10 seconds** to pick manually — auto-selects the best one on timeout or bare Enter
- Supports both legacy `sources.list` and modern DEB822 `ubuntu.sources` formats
- Automatically backs up your current sources file before any change
- **Backup manager** — list, inspect, and restore any previous sources backup

### Blackout resilience
- **Offline dnscrypt bundle** — the repo ships the `dnscrypt-proxy` binary (x86_64) and the DNSCrypt resolver list, so FREE mode still installs and starts when GitHub and `download.dnscrypt.info` are unreachable
- **`prepare-offline.sh`** — run it while you still have Internet to fetch binaries for other architectures (arm64/arm) and refresh everything before an outage

---

## Requirements

- Ubuntu (tested on 20.04, 22.04, 24.04)
- `bash` 4.3+
- `curl`, `dig` (dnsutils), `systemd-resolved`
- Root / sudo access
- `dnscrypt-proxy` — installed automatically if missing (via apt, the bundled offline binary, or a GitHub download)

---

## Installation

**Quick run (one-liner):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alighaffari3000/DNS-Mirror-Helper/main/dns-mirror-helper.sh)
```

> ⚠️ The one-liner fetches only the script itself — **not** the offline dnscrypt bundle. For blackout resilience, clone the full repo instead (see below).

**Full clone (recommended — includes the offline bundle):**
```bash
git clone https://github.com/alighaffari3000/DNS-Mirror-Helper.git
cd DNS-Mirror-Helper
sudo ./dns-mirror-helper.sh
```

---

## Preparing for an Internet blackout

During a blackout, GitHub and `download.dnscrypt.info` are typically unreachable, while domestic (Iran) mirrors stay up. To be ready:

1. **Clone the full repo now** (while online) — the x86_64 dnscrypt binary and the resolver list are committed, so FREE mode keeps working offline out of the box.
2. **For non-x86_64 machines (or to refresh to the latest release), run:**
   ```bash
   ./prepare-offline.sh
   ```
   This downloads the `arm64`/`arm` binaries and a fresh resolver list into `offline/`.
3. **Apply a mirror once while online** — the working mirror is saved as *last known-good*, so during an outage you can re-apply it in seconds via **Mirror Manager → 5**.

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
  1) Switch to International mode (DoH)
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
  5) Quick: re-apply last known-good mirror (fast, no scan)
  0) Back
```

- Choosing **2** or **3** first runs a quick international-connectivity check. If international links are down, option **3** silently scans Iran mirrors only, and option **2** offers to switch to Iran mirrors.
- Choosing **5** re-applies the last mirror that worked — after a quick reachability check — without scanning the whole list. It appears once you've successfully applied a mirror at least once.

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

Edit the `IR_MIRRORS` or `GLOBAL_MIRRORS` arrays. Lines starting with `#` are treated as comments and skipped — known-offline mirrors are kept there for reference under an "offline mirrors" note.

### dnscrypt-proxy config

The script writes its own config to `/etc/dnscrypt-proxy/dnscrypt-proxy.toml`, listening on `127.0.0.1:5053` and using Cloudflare, Google, and Quad9 DoH resolvers (resolver list: DNSCrypt v3). On each FREE-mode activation it seeds the resolver cache from the bundled `offline/public-resolvers.md` if no live cache exists, so DoH can start without Internet. Edit `write_default_config()` in the script to customize.

### Offline bundle

The `offline/` directory holds the assets used when GitHub / `download.dnscrypt.info` are unreachable:

| File | Purpose |
|------|---------|
| `offline/dnscrypt-proxy-linux_x86_64.tar.gz` (+ `.minisig`) | x86_64 binary, committed for a self-contained clone |
| `offline/public-resolvers.md` (+ `.minisig`) | DNSCrypt v3 resolver list, seeded into the cache |
| `offline/VERSION` | bundled dnscrypt-proxy release tag |

Binaries for other architectures are fetched locally by `prepare-offline.sh` and are intentionally not committed.

---

## Restoring a backup

Every time a mirror is changed, the previous sources file is backed up automatically. To restore manually:

```bash
sudo cp /etc/apt/sources.list.bak.2024-01-15-143022 /etc/apt/sources.list
sudo apt update
```

Or use **Mirror Manager → Manage backups** from the interactive menu.

---

## Files & paths used by this script

| Path | Purpose |
|------|---------|
| `/etc/systemd/resolved.conf.d/dns-mirror-helper.conf` | systemd-resolved DNS config |
| `/etc/resolv.conf` | symlinked to the appropriate resolved stub |
| `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` | dnscrypt-proxy config (overwritten on each FREE mode activation) |
| `/var/cache/dnscrypt-proxy/public-resolvers.md` | resolver cache (seeded from the offline bundle) |
| `/var/lib/dns-mirror-helper/last-good` | last known-good mirror URL |
| `/etc/apt/sources.list` or `/etc/apt/sources.list.d/ubuntu.sources` | apt mirror config |
| `/etc/apt/sources.list.bak.*` | automatic backups |

---

## License

MIT
