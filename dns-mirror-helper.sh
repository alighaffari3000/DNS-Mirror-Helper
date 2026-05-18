#!/usr/bin/env bash
set -euo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

########################################
# Colors
########################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

########################################
# Shared helpers
########################################

pause() {
  echo
  read -rp "Press Enter to continue..." _
}

########################################
# DNS: Config & lists
########################################

IR_DNS_LIST=(
  "217.218.155.155"
  "185.20.163.4"
  "78.157.42.101"
  "31.24.234.37"
  "2.189.44.44"
  "185.20.163.2"
  "194.60.210.66"
  "217.218.127.127"
  "2.188.21.130"
  "31.24.200.4"
  "2.185.239.138"
  "5.145.112.39"
  "85.185.85.6"
  "217.219.132.88"
  "178.22.122.100"
  "194.36.174.1"
  "185.53.143.3"
  "80.191.209.105"
  "78.157.42.100"
  "213.176.123.5"
  "185.55.226.26"
  "185.161.112.38"
  "194.225.152.10"
  "2.188.21.131"
  "2.188.21.132"
  "10.202.10.10"
  "46.224.1.42"
  "8.8.8.8"
  "8.8.4.4"
  "1.1.1.1"
  "1.0.0.1"
  "9.9.9.9"
  "149.112.112.112"
)

DNSCRYPT_CONFIG="/etc/dnscrypt-proxy/dnscrypt-proxy.toml"
DNSCRYPT_CONFIG_DIR="/etc/dnscrypt-proxy"
RESOLVED_CONF_DIR="/etc/systemd/resolved.conf.d"
RESOLVED_CONF="$RESOLVED_CONF_DIR/dns-mirror-helper.conf"

########################################
# DNS: DNSCrypt install & setup
########################################

write_default_config() {
  echo ">> Writing default dnscrypt-proxy config..."
  mkdir -p "$DNSCRYPT_CONFIG_DIR"
  mkdir -p /var/log/dnscrypt-proxy
  mkdir -p /var/cache/dnscrypt-proxy

  cat > "$DNSCRYPT_CONFIG" <<'EOF'
##############################################
# dnscrypt-proxy configuration
##############################################

listen_addresses = ['127.0.0.1:5053']

ipv6_servers = false
block_ipv6 = true
require_dnssec = false

server_names = ['cloudflare', 'google', 'quad9-doh']

fallback_resolvers = ['8.8.8.8:53', '1.1.1.1:53']
ignore_system_dns = true

[query_log]
  file = '/var/log/dnscrypt-proxy/query.log'

[nx_log]
  file = '/var/log/dnscrypt-proxy/nx.log'

[sources]
  [sources.'public-resolvers']
  url = 'https://download.dnscrypt.info/resolvers-list/v2/public-resolvers.md'
  cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ''
EOF

  echo -e "${GREEN}>> Config written to $DNSCRYPT_CONFIG${NC}"
}

install_via_apt() {
  echo ">> Trying apt install..."
  if apt-get install -y dnscrypt-proxy >/dev/null 2>&1; then
    echo -e "${GREEN}>> dnscrypt-proxy installed via apt.${NC}"
    systemctl disable dnscrypt-proxy.socket >/dev/null 2>&1 || true
    systemctl stop dnscrypt-proxy.socket >/dev/null 2>&1 || true
    echo ">> systemd socket activation disabled."
    return 0
  else
    echo -e "${YELLOW}>> apt install failed.${NC}"
    return 1
  fi
}

install_via_binary() {
  echo ">> Trying binary install from GitHub..."

  local ARCH BIN_ARCH
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  BIN_ARCH="x86_64" ;;
    aarch64) BIN_ARCH="arm64" ;;
    armv7l)  BIN_ARCH="arm" ;;
    *)
      echo -e "${RED}>> Unsupported architecture: $ARCH${NC}"
      return 1
      ;;
  esac

  local LATEST_URL
  LATEST_URL=$(curl -fsSL https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest \
    | grep "browser_download_url" \
    | grep "linux_${BIN_ARCH}" \
    | head -1 \
    | cut -d '"' -f4)

  if [ -z "$LATEST_URL" ]; then
    echo -e "${RED}>> Could not fetch download URL from GitHub.${NC}"
    return 1
  fi

  echo ">> Downloading: $LATEST_URL"
  local TMP_DIR
  TMP_DIR=$(mktemp -d)
  curl -fsSL "$LATEST_URL" -o "$TMP_DIR/dnscrypt.tar.gz"
  tar -xzf "$TMP_DIR/dnscrypt.tar.gz" -C "$TMP_DIR"

  local BIN_PATH
  BIN_PATH=$(find "$TMP_DIR" -name "dnscrypt-proxy" -type f | head -1)

  if [ -z "$BIN_PATH" ]; then
    echo -e "${RED}>> Binary not found in archive.${NC}"
    rm -rf "$TMP_DIR"
    return 1
  fi

  install -m 755 "$BIN_PATH" /usr/local/bin/dnscrypt-proxy
  rm -rf "$TMP_DIR"

  cat > /etc/systemd/system/dnscrypt-proxy.service <<EOF
[Unit]
Description=DNSCrypt-proxy client
Documentation=https://github.com/DNSCrypt/dnscrypt-proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/dnscrypt-proxy -config $DNSCRYPT_CONFIG
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  echo -e "${GREEN}>> dnscrypt-proxy installed via binary.${NC}"
  return 0
}

ensure_dnscrypt_installed() {
  if command -v dnscrypt-proxy >/dev/null 2>&1; then
    echo -e "${GREEN}>> dnscrypt-proxy is already installed.${NC}"
  else
    echo -e "${YELLOW}>> dnscrypt-proxy not found. Starting installation...${NC}"

    local installed=0
    install_via_apt && installed=1

    if [ "$installed" -eq 0 ]; then
      install_via_binary && installed=1
    fi

    if [ "$installed" -eq 0 ]; then
      echo -e "${RED}>> Installation failed via apt and binary.${NC}"
      echo -e "${YELLOW}>> Falling back to MELLI mode...${NC}"
      switch_melli
      return 1
    fi
  fi

  write_default_config

  systemctl enable dnscrypt-proxy >/dev/null 2>&1 || true
  systemctl start dnscrypt-proxy >/dev/null 2>&1 || true

  sleep 2
  if systemctl is-active --quiet dnscrypt-proxy; then
    echo -e "${GREEN}>> dnscrypt-proxy is running successfully.${NC}"
    return 0
  else
    echo -e "${RED}>> dnscrypt-proxy failed to start after install.${NC}"
    echo -e "${YELLOW}>> Falling back to MELLI mode...${NC}"
    switch_melli
    return 1
  fi
}

########################################
# DNS: systemd-resolved helpers
########################################

resolved_use_dnscrypt() {
  mkdir -p "$RESOLVED_CONF_DIR"
  cat > "$RESOLVED_CONF" <<EOF
[Resolve]
DNS=127.0.0.1:5053
DNSStubListener=no
EOF
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  if ! systemctl restart systemd-resolved >/dev/null 2>&1; then
    echo "WARNING: failed to restart systemd-resolved" >&2
  fi
  echo ">> systemd-resolved → dnscrypt-proxy (127.0.0.1:5053)"
}

resolved_use_direct() {
  local servers="$1"
  mkdir -p "$RESOLVED_CONF_DIR"
  cat > "$RESOLVED_CONF" <<EOF
[Resolve]
DNS=$servers
DNSStubListener=yes
EOF
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  if ! systemctl restart systemd-resolved >/dev/null 2>&1; then
    echo "WARNING: failed to restart systemd-resolved" >&2
  fi
  echo ">> systemd-resolved → direct DNS ($servers)"
}

########################################
# DNS: Mode detection
########################################

dns_check_mode() {
  if systemctl is-active --quiet dnscrypt-proxy 2>/dev/null; then
    echo "FREE (DoH via dnscrypt-proxy)"
  else
    echo "MELLI (Auto-selected DNS)"
  fi
}

########################################
# DNS: FREE mode
########################################

switch_free() {
  echo ">> Switching to FREE mode (DoH via dnscrypt-proxy)..."
  ensure_dnscrypt_installed || return
  systemctl start dnscrypt-proxy >/dev/null 2>&1 || true
  resolved_use_dnscrypt
  echo ">> dnscrypt-proxy status: $(systemctl is-active dnscrypt-proxy || true)"
}

########################################
# DNS: MELLI mode
########################################

select_best_dns() {
  echo ">> Testing DNS servers..."
  WORKING_DNS=()

  for DNS in "${IR_DNS_LIST[@]}"; do
    if dig @"$DNS" google.com +time=1 +short >/dev/null 2>&1; then
      echo -e "${GREEN}[OK]${NC} $DNS"
      WORKING_DNS+=("$DNS")
    else
      echo -e "${RED}[FAIL]${NC} $DNS"
    fi

    if [ "${#WORKING_DNS[@]}" -ge 2 ]; then
      break
    fi
  done
}

switch_melli() {
  echo ">> Switching to MELLI mode (Auto DNS selection)..."
  systemctl stop dnscrypt-proxy >/dev/null 2>&1 || true

  select_best_dns

  if [ "${#WORKING_DNS[@]}" -eq 0 ]; then
    echo -e "${RED}No working DNS found!${NC}"
    return
  fi

  resolved_use_direct "${WORKING_DNS[*]}"
  echo ">> DNS set to: ${WORKING_DNS[*]}"
  echo ">> dnscrypt-proxy status: $(systemctl is-active dnscrypt-proxy || true)"
}

########################################
# DNS: AUTO mode
########################################

dns_auto_select() {
  echo ">> Auto-detecting best mode (robust check)..."
  ensure_dnscrypt_installed || return

  systemctl start dnscrypt-proxy >/dev/null 2>&1 || true
  resolved_use_dnscrypt

  echo ">> Warming up dnscrypt-proxy..."
  sleep 2

  local ok=0
  for i in 1 2 3; do
    echo ">> Test attempt $i..."
    if dig google.com >/dev/null 2>&1 && curl -fs --max-time 5 https://api.ipify.org >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 1
  done

  if [ "$ok" -eq 1 ]; then
    echo ">> International connectivity detected (DNS + HTTPS OK)."
    echo ">> Staying in FREE mode."
  else
    echo ">> International connectivity seems DOWN after retries. Falling back to MELLI mode."
    switch_melli
  fi
}

########################################
# DNS: Status
########################################

dns_show_status() {
  echo "=============================="
  echo " Current DNS mode: $(dns_check_mode)"
  echo "------------------------------"
  echo "/etc/resolv.conf:"

  if [ -L /etc/resolv.conf ]; then
    local target
    target="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    echo "symlink -> ${target:-broken link}"
  fi

  if [ -e /etc/resolv.conf ]; then
    cat /etc/resolv.conf
  else
    echo "ERROR: /etc/resolv.conf does not exist or is a broken symlink."
    echo "Hint: systemd-resolved may be inactive, or the target under /run/systemd/resolve/ is missing."
  fi

  echo "=============================="
}

########################################
# DNS: Safe reset
########################################

dns_safe_reset() {
  echo ">> Safe reset: restarting DNS services and flushing caches..."
  systemctl restart dnscrypt-proxy >/dev/null 2>&1 || true
  if command -v resolvectl >/dev/null 2>&1; then
    resolvectl flush-caches || true
  fi
  echo ">> Done."
}

########################################
# DNS: Connectivity tests
########################################

test_cmd() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} $label"
    return 0
  else
    echo -e "${RED}[FAILED]${NC} $label"
    return 1
  fi
}

dns_run_tests() {
  echo ">> Running DNS & connectivity tests..."
  local fails=0

  test_cmd "DNS resolve google.com"    nslookup google.com      || fails=$((fails+1))
  test_cmd "DNS resolve github.com"    nslookup github.com      || fails=$((fails+1))
  test_cmd "HTTP IP check (api.ipify.org)"  curl -fs https://api.ipify.org   || fails=$((fails+1))
  test_cmd "HTTP IP check (icanhazip.com)"  curl -fs https://icanhazip.com   || fails=$((fails+1))

  echo
  if [ "$fails" -eq 0 ]; then
    echo -e "${GREEN}All tests passed. Connectivity looks GOOD.${NC}"
  else
    echo -e "${RED}$fails test(s) failed. Connectivity has issues.${NC}"
  fi
}

########################################
# DNS: Manual entry
########################################

is_valid_ip() {
  local ip="$1"
  local re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  if [[ ! "$ip" =~ $re ]]; then
    return 1
  fi
  local IFS='.'
  local -a octets=($ip)
  for octet in "${octets[@]}"; do
    if [[ "$octet" -gt 255 ]]; then
      return 1
    fi
  done
  return 0
}

switch_manual_dns() {
  echo ">> Manual DNS entry"
  echo "   Enter one or more DNS addresses, comma-separated."
  echo "   Example: 1.1.1.1, 8.8.8.8"
  echo ""
  read -rp "DNS addresses: " raw_input

  # Parse: split on commas, trim whitespace
  local -a VALID_DNS=()
  local -a INVALID_DNS=()

  IFS=',' read -ra parts <<< "$raw_input"
  for part in "${parts[@]}"; do
    # Trim leading/trailing whitespace
    local addr="${part#"${part%%[![:space:]]*}"}"
    addr="${addr%"${addr##*[![:space:]]}"}"

    [[ -z "$addr" ]] && continue

    if is_valid_ip "$addr"; then
      VALID_DNS+=("$addr")
      echo -e "${GREEN}[VALID]${NC} $addr"
    else
      INVALID_DNS+=("$addr")
      echo -e "${RED}[INVALID]${NC} $addr — skipped"
    fi
  done

  echo ""

  if [[ ${#VALID_DNS[@]} -eq 0 ]]; then
    echo -e "${RED}No valid DNS addresses provided. Nothing changed.${NC}"
    return
  fi

  if [[ ${#INVALID_DNS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Warning: ${#INVALID_DNS[@]} invalid address(es) skipped.${NC}"
    echo ""
  fi

  echo ">> Applying DNS: ${VALID_DNS[*]}"
  systemctl stop dnscrypt-proxy >/dev/null 2>&1 || true
  resolved_use_direct "${VALID_DNS[*]}"
  echo ">> DNS set to: ${VALID_DNS[*]}"
  echo ">> dnscrypt-proxy status: $(systemctl is-active dnscrypt-proxy || true)"
}

########################################
# DNS: Menu
########################################

dns_menu() {
  while true; do
    clear
    dns_show_status
    echo
    echo "DNS Manager — Choose an option:"
    echo "  1) Switch to FREE mode (DoH)"
    echo "  2) Switch to MELLI mode (Auto DNS select)"
    echo "  3) Auto-select best mode"
    echo "  4) Manual DNS entry"
    echo "  5) Safe reset DNS services"
    echo "  6) Run connectivity tests"
    echo "  0) Back"
    echo
    read -rp "Enter choice [0-6]: " choice
    echo

    case "$choice" in
      1) switch_free;        pause ;;
      2) switch_melli;       pause ;;
      3) dns_auto_select;    pause ;;
      4) switch_manual_dns;  pause ;;
      5) dns_safe_reset;     pause ;;
      6) dns_run_tests;      pause ;;
      0) return ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

########################################
# Mirror: Config & lists
########################################

CODENAME=$(lsb_release -cs 2>/dev/null \
  || (source /etc/os-release && echo "${VERSION_CODENAME:-noble}"))

if [[ -z "${CODENAME}" ]]; then
  echo -e "${RED}Could not detect Ubuntu codename.${NC}"
  exit 1
fi

IR_MIRRORS=(
  "http://linux-mirror.liara.ir/repository/ubuntu/"
  "https://mirror.arvancloud.ir/ubuntu"
#  "https://mirror.manageit.ir/ubuntu"
#  "http://mirror.asiatech.ir/ubuntu"
  "http://mirror.iranserver.com/ubuntu"
  "https://archive.ubuntu.petiak.ir/ubuntu"
#  "https://ubuntu.hostiran.ir/ubuntuarchive"
  "https://mirror.iranserver.com/ubuntu"
  "https://ir.ubuntu.sindad.cloud/ubuntu"
  "https://mirrors.pardisco.co/ubuntu"
#  "http://mirror.aminidc.com/ubuntu"
#  "http://mirror.faraso.org/ubuntu"
  "https://ir.archive.ubuntu.com/ubuntu"
#  "https://ubuntu-mirror.kimiahost.com"
#  "https://ubuntu.bardia.tech"
  "https://mirror.0-1.cloud/ubuntu"
#  "http://linuxmirrors.ir/pub/ubuntu"
#  "http://repo.iut.ac.ir/repo/Ubuntu"
#  "https://ubuntu.shatel.ir/ubuntu"
#  "http://ubuntu.byteiran.com/ubuntu"
#  "https://mirror.rasanegar.com/ubuntu"
#  "http://mirrors.sharif.ir/ubuntu"
#  "http://mirror.ut.ac.ir/ubuntu"
#  "http://repo.iut.ac.ir/repo/ubuntu"
#  "https://mirror.parsdev.com/ubuntu"
#  "https://mirror.mobinhost.com/ubuntu"
#  "https://linuxmirrors.ir/pub/ubuntu"
#  "https://mirrors.kubarcloud.com/ubuntu"
#  "https://repo.abrha.net/ubuntu"
#  "https://en-mirror.ir/ubuntu"
#  "https://mirror.afranet.com/ubuntu"
#  "https://mirror.atlantiscloud.ir/ubuntu"
#  "https://mirror.digitalvps.ir/ubuntu"
#  "https://iran.chabokan.net/ubuntu"
)

GLOBAL_MIRRORS=(
  "http://archive.ubuntu.com/ubuntu"
  "https://archive.ubuntu.com/ubuntu"
  "https://us.archive.ubuntu.com/ubuntu"
  "https://de.archive.ubuntu.com/ubuntu"
  "https://nl.archive.ubuntu.com/ubuntu"
  "https://fr.archive.ubuntu.com/ubuntu"
  "https://gb.archive.ubuntu.com/ubuntu"
  "https://ca.archive.ubuntu.com/ubuntu"
)

UA="Mozilla/5.0 (X11; Ubuntu; Linux x86_64)"
MAX_RETRIES=2
VALIDATION_RETRIES=3

########################################
# Mirror: Non-blocking input helpers
########################################

SKIP_REQUESTED=false
OLD_STTY=""

setup_nonblock_input() {
  OLD_STTY=$(stty -g 2>/dev/null || true)
  stty -echo -icanon min 0 time 0 2>/dev/null || true
}

restore_input() {
  [[ -n "$OLD_STTY" ]] && stty "$OLD_STTY" 2>/dev/null || true
}

check_skip() {
  local ch
  ch=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
  if [[ "$ch" == "0a" || "$ch" == "0d" ]]; then
    SKIP_REQUESTED=true
  fi
}

########################################
# Mirror: Test helpers
########################################

check_suite() {
  local base="$1" suite="$2" retry="${3:-0}"
  local url="$base/dists/$suite/InRelease"
  local code

  code=$(curl -4 --ipv4 -A "$UA" -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 6 --max-time 10 -L "$url" 2>/dev/null || echo "000")

  if [[ "$code" != "200" ]] && [[ $retry -lt $MAX_RETRIES ]]; then
    sleep 1
    check_suite "$base" "$suite" $((retry + 1))
    return $?
  fi

  [[ "$code" == "200" ]]
}

validate_mirror() {
  local base="$1"
  local test_file="$base/dists/$CODENAME/main/binary-amd64/Packages.gz"

  for i in $(seq 1 $VALIDATION_RETRIES); do
    local size
    size=$(curl -4 --ipv4 -A "$UA" -sL --connect-timeout 5 --max-time 8 \
      -w "%{size_download}" -o /dev/null "$test_file" 2>/dev/null || echo "0")

    if [[ "${size:-0}" -gt 500000 ]]; then
      return 0
    fi

    [[ $i -lt $VALIDATION_RETRIES ]] && sleep 2
  done

  return 1
}

is_mirror_syncing() {
  local base="$1"
  local inrelease_url="$base/dists/$CODENAME/InRelease"

  local last_modified
  last_modified=$(curl -4 --ipv4 -A "$UA" -sI --connect-timeout 5 \
    "$inrelease_url" 2>/dev/null | grep -i "last-modified:" | cut -d' ' -f2-)

  if [[ -n "$last_modified" ]]; then
    local mod_epoch now_epoch diff
    mod_epoch=$(date -d "$last_modified" +%s 2>/dev/null || echo "0")
    now_epoch=$(date +%s)
    diff=$((now_epoch - mod_epoch))
    [[ $diff -lt 900 ]]
  else
    return 1
  fi
}

########################################
# Mirror: Test & score a list of mirrors
########################################

# Populates global MIRROR_RESULTS array: "SCORE LAT_MS SPEED_KB URL"
test_mirrors() {
  local -n _mirrors=$1   # nameref to the array passed in
  MIRROR_RESULTS=()

  local TESTED=0
  local TOTAL=${#_mirrors[@]}

  setup_nonblock_input
  trap 'restore_input' EXIT INT TERM

  for BASE in "${_mirrors[@]}"; do
    [[ -z "$BASE" || "$BASE" == \#* ]] && continue
    TESTED=$((TESTED + 1))

    SKIP_REQUESTED=false
    check_skip

    echo -n -e "[${TESTED}/${TOTAL}] Testing ${YELLOW}$BASE${NC} ... "

    if is_mirror_syncing "$BASE"; then
      echo -e "${YELLOW}syncing (skipped)${NC}"
      continue
    fi

    check_skip
    if [[ "$SKIP_REQUESTED" == "true" ]]; then
      echo -e "${YELLOW}skipped by user${NC}"
      SKIP_REQUESTED=false
      continue
    fi

    if ! check_suite "$BASE" "$CODENAME" \
       || ! check_suite "$BASE" "$CODENAME-updates" \
       || ! check_suite "$BASE" "$CODENAME-backports"; then
      echo -e "${RED}unreachable${NC}"
      continue
    fi

    check_skip
    if [[ "$SKIP_REQUESTED" == "true" ]]; then
      echo -e "${YELLOW}skipped by user${NC}"
      SKIP_REQUESTED=false
      continue
    fi

    local BASE_DIST="$BASE/dists/$CODENAME"

    local LATENCY LAT_MS
    LATENCY=$(LC_ALL=C curl -4 --ipv4 -A "$UA" -s -L --connect-timeout 6 \
      -w "%{time_total}" -o /dev/null "$BASE_DIST/InRelease" 2>/dev/null || echo "0")
    LATENCY="${LATENCY:-0}"
    LAT_MS=$(LC_ALL=C awk "BEGIN {printf \"%d\", $LATENCY*1000}")

    check_skip
    if [[ "$SKIP_REQUESTED" == "true" ]]; then
      echo -e "${YELLOW}skipped by user${NC}"
      SKIP_REQUESTED=false
      continue
    fi

    local PKG_URL="$BASE_DIST/main/binary-amd64/Packages.gz"
    local STATS BYTES TIME CODE
    STATS=$(LC_ALL=C curl -4 --ipv4 -A "$UA" -s -L --connect-timeout 8 --max-time 12 \
      --range 0-2097152 -o /dev/null -w "%{size_download} %{time_total} %{http_code}" \
      "$PKG_URL" 2>/dev/null || echo "0 0 000")

    BYTES=$(awk '{print $1}' <<< "$STATS")
    TIME=$(awk '{print $2}' <<< "$STATS")
    CODE=$(awk '{print $3}' <<< "$STATS")

    if [[ "$CODE" != "200" && "$CODE" != "206" ]] || [[ "${BYTES:-0}" -lt 1000 ]]; then
      STATS=$(LC_ALL=C curl -4 --ipv4 -A "$UA" -s -L --connect-timeout 6 --max-time 8 \
        -o /dev/null -w "%{size_download} %{time_total}" \
        "$BASE_DIST/InRelease" 2>/dev/null || echo "0 0")
      BYTES=$(awk '{print $1}' <<< "$STATS")
      TIME=$(awk '{print $2}' <<< "$STATS")
    fi

    local SPEED_KB=0
    if [[ "${BYTES:-0}" -gt 0 ]] && LC_ALL=C awk "BEGIN {exit !($TIME > 0.01)}"; then
      SPEED_KB=$(LC_ALL=C awk "BEGIN {printf \"%d\", $BYTES/$TIME/1024}")
    fi

    if [[ "$SPEED_KB" -le 5 ]]; then
      echo -e "${RED}too slow (${SPEED_KB} KB/s)${NC}"
      continue
    fi

    local SCORE
    SCORE=$(LC_ALL=C awk "BEGIN {printf \"%d\", ($LAT_MS*0.6) + (100000/$SPEED_KB)*0.4 }")

    echo -e "${GREEN}OK${NC} | ${LAT_MS}ms | ${SPEED_KB} KB/s | score=${SCORE}"
    MIRROR_RESULTS+=("$SCORE $LAT_MS $SPEED_KB $BASE")
  done

  restore_input
  trap - EXIT INT TERM
}

########################################
# Mirror: Apply selected mirror
########################################

apply_mirror() {
  local SELECTED_BASE="$1"

  echo -n "Validating selected mirror... "
  if ! validate_mirror "$SELECTED_BASE"; then
    echo -e "${RED}FAILED${NC}"
    echo -e "${YELLOW}Warning: Selected mirror failed validation. It may be incomplete or syncing.${NC}"
    read -r -p "Continue anyway? (y/N): " CONT
    if [[ ! "$CONT" =~ ^[Yy]$ ]]; then
      echo "Cancelled."
      return 1
    fi
  else
    echo -e "${GREEN}OK${NC}"
  fi

  local SOURCES_FILE SOURCES_FORMAT
  if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
    SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"
    SOURCES_FORMAT="deb822"
  elif [[ -f /etc/apt/sources.list ]]; then
    SOURCES_FILE="/etc/apt/sources.list"
    SOURCES_FORMAT="legacy"
  else
    echo -e "${RED}Could not find apt sources file.${NC}"
    return 1
  fi

  echo -e "Sources file: ${YELLOW}$SOURCES_FILE${NC} (format: $SOURCES_FORMAT)"

  if [[ "$SOURCES_FORMAT" == "deb822" ]] && [[ -f /etc/apt/sources.list ]]; then
    local ACTIVE_LINES
    ACTIVE_LINES=$(grep -cE '^deb ' /etc/apt/sources.list 2>/dev/null || echo 0)
    if [[ "$ACTIVE_LINES" -gt 0 ]]; then
      echo -n "Clearing duplicate entries from /etc/apt/sources.list ... "
      sudo cp /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%F-%H%M%S)" 2>/dev/null || true
      echo "# Cleared by dns-mirror-helper.sh on $(date) — entries moved to ubuntu.sources" \
        | sudo tee /etc/apt/sources.list > /dev/null
      echo -e "${GREEN}OK${NC}"
    fi
  fi

  local BACKUP_FILE="${SOURCES_FILE}.bak.$(date +%F-%H%M%S)"
  echo -n "Creating backup: $BACKUP_FILE ... "
  if sudo cp "$SOURCES_FILE" "$BACKUP_FILE" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAILED${NC}"
    return 1
  fi

  local SECURITY_BASE="$SELECTED_BASE"

  echo -n "Writing $SOURCES_FILE ... "
  if [[ "$SOURCES_FORMAT" == "deb822" ]]; then
    {
      echo "# Mirror selected by dns-mirror-helper.sh on $(date)"
      echo "# Backup: $BACKUP_FILE"
      echo ""
      echo "Types: deb"
      echo "URIs: $SELECTED_BASE"
      echo "Suites: $CODENAME $CODENAME-updates $CODENAME-backports $CODENAME-security"
      echo "Components: main restricted universe multiverse"
      echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
    } | sudo tee "$SOURCES_FILE" > /dev/null
  else
    {
      echo "# Mirror selected by dns-mirror-helper.sh on $(date)"
      echo "# Backup: $BACKUP_FILE"
      echo ""
      echo "deb $SELECTED_BASE $CODENAME main restricted universe multiverse"
      echo "deb $SELECTED_BASE $CODENAME-updates main restricted universe multiverse"
      echo "deb $SELECTED_BASE $CODENAME-backports main restricted universe multiverse"
      echo "deb $SECURITY_BASE $CODENAME-security main restricted universe multiverse"
      echo ""
      echo "# Uncomment for source packages:"
      echo "# deb-src $SELECTED_BASE $CODENAME main restricted universe multiverse"
      echo "# deb-src $SELECTED_BASE $CODENAME-updates main restricted universe multiverse"
    } | sudo tee "$SOURCES_FILE" > /dev/null
  fi
  echo -e "${GREEN}OK${NC}"

  echo ""
  echo -e "${BLUE}Running apt update...${NC}"
  if sudo apt update; then
    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}Success!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "Mirror configured: ${YELLOW}$SELECTED_BASE${NC}"
    echo -e "Backup saved to:   ${YELLOW}$BACKUP_FILE${NC}"
    echo ""
    echo -e "To restore previous configuration:"
    echo -e "  ${YELLOW}sudo cp $BACKUP_FILE $SOURCES_FILE && sudo apt update${NC}"
  else
    echo ""
    echo -e "${RED}apt update FAILED!${NC}"
    echo -e "The mirror may be incomplete or syncing."
    echo ""
    echo -e "To restore previous configuration:"
    echo -e "  ${YELLOW}sudo cp $BACKUP_FILE $SOURCES_FILE && sudo apt update${NC}"
    return 1
  fi
}

########################################
# Mirror: Show sorted results & prompt
# with 10s countdown; auto-select on
# timeout or bare Enter
########################################

select_from_results() {
  # MIRROR_RESULTS must be populated before calling this
  if [[ ${#MIRROR_RESULTS[@]} -eq 0 ]]; then
    echo -e "${RED}No valid mirrors found.${NC}"
    return 1
  fi

  local -a SORTED
  mapfile -t SORTED < <(printf "%s\n" "${MIRROR_RESULTS[@]}" | sort -n)

  echo ""
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}Results (sorted by speed/latency):${NC}"
  echo -e "${BLUE}=====================================${NC}"

  for i in "${!SORTED[@]}"; do
    local LINE="${SORTED[$i]}"
    local SCORE LAT SPD URL
    SCORE=$(awk '{print $1}' <<< "$LINE")
    LAT=$(awk '{print $2}' <<< "$LINE")
    SPD=$(awk '{print $3}' <<< "$LINE")
    URL=$(awk '{print $4}' <<< "$LINE")
    echo -e "  $((i+1)). ${GREEN}$URL${NC}"
    echo -e "     Latency: ${LAT}ms | Speed: ${SPD} KB/s | Score: ${SCORE}"
  done

  echo ""
  local TOTAL_RESULTS=${#SORTED[@]}
  local SELECTED_IDX=0   # default: best (index 0)
  local USER_INPUT=""

  # 10-second countdown with non-blocking read
  echo -e "Enter mirror number (1-${TOTAL_RESULTS}) or press ${YELLOW}Enter${NC} to auto-select best."
  echo -n "Auto-selecting in "

  local OLD_STTY_SEL
  OLD_STTY_SEL=$(stty -g 2>/dev/null || true)
  stty -echo -icanon min 0 time 0 2>/dev/null || true

  local DEADLINE=$(( $(date +%s) + 10 ))
  local CHOSEN=false

  while true; do
    local NOW
    NOW=$(date +%s)
    local REMAINING=$(( DEADLINE - NOW ))

    if [[ $REMAINING -le 0 ]]; then
      echo -e "\n>> Timeout reached. Auto-selecting best mirror."
      break
    fi

    # Print remaining seconds (overwrite same line)
    echo -ne "\rAuto-selecting in ${YELLOW}${REMAINING}s${NC} (or enter number + Enter): "

    # Try to read one character
    local CH
    CH=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')

    if [[ -z "$CH" ]]; then
      sleep 0.3
      continue
    fi

    # Enter key (bare) → auto-select
    if [[ "$CH" == "0a" || "$CH" == "0d" ]]; then
      echo ""
      echo ">> Auto-selecting best mirror."
      break
    fi

    # Digit → accumulate
    local CHAR
    CHAR=$(printf "\\x${CH}" 2>/dev/null || true)
    if [[ "$CHAR" =~ ^[0-9]$ ]]; then
      USER_INPUT+="$CHAR"
      echo -ne "\rYour choice: ${USER_INPUT}                    "
    fi

    # Backspace
    if [[ "$CH" == "7f" || "$CH" == "08" ]]; then
      USER_INPUT="${USER_INPUT%?}"
      echo -ne "\rYour choice: ${USER_INPUT}                    "
    fi

    # Second Enter after digits → confirm
    # We detect a follow-up Enter by checking if USER_INPUT is non-empty
    # and current char is Enter — handled above; so we need a second Enter pass.
    # Simpler: after accumulating digits, wait for Enter separately.
    # Restructure: if USER_INPUT non-empty and we got Enter, we already broke above.
    # So digits just accumulate; user must press Enter to confirm (caught above).
  done

  stty "$OLD_STTY_SEL" 2>/dev/null || true

  if [[ -n "$USER_INPUT" ]]; then
    if [[ "$USER_INPUT" =~ ^[0-9]+$ ]] \
       && [[ "$USER_INPUT" -ge 1 ]] \
       && [[ "$USER_INPUT" -le "$TOTAL_RESULTS" ]]; then
      SELECTED_IDX=$(( USER_INPUT - 1 ))
    else
      echo -e "${YELLOW}Invalid choice, falling back to best mirror.${NC}"
    fi
  fi

  local SELECTED_LINE="${SORTED[$SELECTED_IDX]}"
  local SELECTED_BASE
  SELECTED_BASE=$(awk '{print $4}' <<< "$SELECTED_LINE")

  echo ""
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${GREEN}Selected mirror:${NC} ${YELLOW}$SELECTED_BASE${NC}"
  echo -e "${BLUE}=====================================${NC}"

  apply_mirror "$SELECTED_BASE"
}

########################################
# Mirror: Source picker submenu
########################################

mirror_pick_source() {
  local src_choice="$1"
  echo ""

  local -a SELECTED_POOL=()

  case "$src_choice" in
    1)
      # Filter out commented entries
      for m in "${IR_MIRRORS[@]}"; do
        [[ "$m" == \#* || -z "$m" ]] && continue
        SELECTED_POOL+=("$m")
      done
      ;;
    2)
      SELECTED_POOL=("${GLOBAL_MIRRORS[@]}")
      ;;
    3)
      for m in "${IR_MIRRORS[@]}"; do
        [[ "$m" == \#* || -z "$m" ]] && continue
        SELECTED_POOL+=("$m")
      done
      SELECTED_POOL+=("${GLOBAL_MIRRORS[@]}")
      ;;
    0) return ;;
    *) echo "Invalid choice."; return ;;
  esac

  if [[ ${#SELECTED_POOL[@]} -eq 0 ]]; then
    echo -e "${RED}No mirrors available in selected pool.${NC}"
    return
  fi

  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}Testing mirrors...${NC}"
  echo -e "${YELLOW}  Press Enter at any time to skip current mirror${NC}"
  echo -e "${BLUE}=====================================${NC}"

  test_mirrors SELECTED_POOL
  select_from_results
}

########################################
# Mirror: Manage backups
########################################

mirror_manage_backups() {
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}Backup Manager${NC}"
  echo -e "${BLUE}=====================================${NC}"

  local -a BACKUPS
  mapfile -t BACKUPS < <(
    { ls /etc/apt/sources.list.bak.* /etc/apt/sources.list.d/ubuntu.sources.bak.* 2>/dev/null || true; } \
    | grep -v '^$' | sort -r || true
  )

  if [[ ${#BACKUPS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No backups found.${NC}"
    echo -e "Backups are created automatically when you change your mirror."
    echo ""
    return
  fi

  echo -e "Found ${GREEN}${#BACKUPS[@]}${NC} backup(s):\n"

  for i in "${!BACKUPS[@]}"; do
    local bfile="${BACKUPS[$i]}"
    local bdate mirrors

    bdate=$(basename "$bfile" \
      | sed 's/sources.list.bak.//' \
      | sed 's/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1 \2:\3:\4/')

    mirrors=$(grep -E '^deb' "$bfile" 2>/dev/null \
      | sed 's/^\(deb\(-src\)\?\)[[:space:]]\+\(\[[^]]*\][[:space:]]\+\)\?//' \
      | awk '{print $1}' | grep -E '^https?://' | sort -u | tr '\n' ' ' || true)

    if [[ -z "${mirrors// /}" ]]; then
      mirrors=$(grep -E '^URIs:' "$bfile" 2>/dev/null \
        | sed 's/^URIs:[[:space:]]*//' | tr ' ' '\n' \
        | grep -E '^https?://' | sort -u | tr '\n' ' ' || true)
    fi

    [[ -z "${mirrors// /}" ]] && mirrors="(unknown format)"

    echo -e "  $((i+1)). ${YELLOW}$bdate${NC}"
    echo -e "     File: $bfile"
    echo -e "     Mirrors: ${GREEN}$mirrors${NC}"
    echo ""
  done

  read -r -p "Enter backup number to restore (or 'q' to go back): " BCHOICE

  if [[ "$BCHOICE" == "q" ]]; then
    echo "Cancelled."
    return
  fi

  if ! [[ "$BCHOICE" =~ ^[0-9]+$ ]] \
     || [[ "$BCHOICE" -lt 1 ]] \
     || [[ "$BCHOICE" -gt "${#BACKUPS[@]}" ]]; then
    echo -e "${RED}Invalid choice.${NC}"
    return
  fi

  local SELECTED_BACKUP="${BACKUPS[$((BCHOICE-1))]}"

  echo ""
  echo -e "${BLUE}Selected backup:${NC} ${YELLOW}$SELECTED_BACKUP${NC}"
  echo ""
  echo -e "${YELLOW}Content:${NC}"
  {
    grep -E '^deb' "$SELECTED_BACKUP" 2>/dev/null || true
    grep -E '^URIs:|^Suites:|^Components:|^Types:' "$SELECTED_BACKUP" 2>/dev/null || true
  } | sort -u | while read -r line; do
    echo -e "  ${GREEN}$line${NC}"
  done
  echo ""

  read -r -p "Are you sure you want to restore this backup? (y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    return
  fi

  local ORIGINAL_FILE
  if [[ "$SELECTED_BACKUP" == *"ubuntu.sources.bak."* ]]; then
    ORIGINAL_FILE="/etc/apt/sources.list.d/ubuntu.sources"
  else
    ORIGINAL_FILE="/etc/apt/sources.list"
  fi

  local PRE_RESTORE_BACKUP="${ORIGINAL_FILE}.bak.$(date +%F-%H%M%S)"
  echo -n "Saving current config as backup: $PRE_RESTORE_BACKUP ... "
  if sudo cp "$ORIGINAL_FILE" "$PRE_RESTORE_BACKUP" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAILED${NC}"
    return 1
  fi

  echo -n "Restoring backup to $ORIGINAL_FILE ... "
  if sudo cp "$SELECTED_BACKUP" "$ORIGINAL_FILE" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAILED${NC}"
    return 1
  fi

  echo ""
  echo -e "${BLUE}Running apt update...${NC}"
  if sudo apt update; then
    echo ""
    echo -e "${GREEN}Restore successful!${NC}"
    echo -e "Restored from: ${YELLOW}$SELECTED_BACKUP${NC}"
    echo -e "Previous config saved to: ${YELLOW}$PRE_RESTORE_BACKUP${NC}"
  else
    echo ""
    echo -e "${RED}apt update FAILED after restore!${NC}"
    echo -e "To undo: ${YELLOW}sudo cp $PRE_RESTORE_BACKUP $ORIGINAL_FILE && sudo apt update${NC}"
    return 1
  fi
}

########################################
# Mirror: Menu
########################################

mirror_menu() {
  while true; do
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}Mirror Manager${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "Ubuntu codename: ${GREEN}$CODENAME${NC}"
    echo ""
    echo "  1) Iran mirrors only"
    echo "  2) International mirrors only"
    echo "  3) Iran + International"
    echo "  4) Manage backups"
    echo "  0) Back"
    echo ""
    read -rp "Enter choice [0-4]: " choice
    echo ""

    case "$choice" in
      1|2|3) mirror_pick_source "$choice"; pause ;;
      4)     mirror_manage_backups; pause ;;
      0)     return ;;
      *)     echo "Invalid choice."; pause ;;
    esac
  done
}

########################################
# Main Menu
########################################

main_menu() {
  while true; do
    clear
    echo -e "${CYAN}=====================================${NC}"
    echo -e "${CYAN}  DNS & Mirror Helper${NC}"
    echo -e "${CYAN}=====================================${NC}"
    echo ""
    echo "  1) DNS Manager"
    echo "  2) Mirror Manager"
    echo "  0) Exit"
    echo ""
    read -rp "Enter choice [0-2]: " choice
    echo ""

    case "$choice" in
      1) dns_menu ;;
      2) mirror_menu ;;
      0) echo "Bye."; exit 0 ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

main_menu
