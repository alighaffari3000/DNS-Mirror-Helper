#!/usr/bin/env bash
set -euo pipefail

########################################################################
# prepare-offline.sh
#
# Run this WHILE YOU STILL HAVE INTERNET (ideally right after cloning)
# to populate the offline/ directory with the dnscrypt-proxy binaries
# and the DNSCrypt resolver list.
#
# During an Internet blackout, dns-mirror-helper.sh falls back to these
# bundled assets so that FREE (DoH) mode keeps working even when GitHub
# and download.dnscrypt.info are unreachable.
#
# The x86_64 bundle + resolver list ship in the git repo already; this
# script is mainly for:
#   * fetching binaries for other architectures (arm64, arm, i386)
#   * refreshing everything to the latest release before an outage
########################################################################

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
OFFLINE_DIR="$SCRIPT_DIR/offline"
mkdir -p "$OFFLINE_DIR"

# Architectures to bundle. Add "i386" here if you need 32-bit x86.
ARCHES=("x86_64" "arm64" "arm")

echo ">> Resolving latest dnscrypt-proxy release tag..."
VER=$(curl -fsSL https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest \
  | grep '"tag_name"' | head -1 | cut -d '"' -f4 || true)

if [[ -z "$VER" ]]; then
  echo -e "${RED}>> Could not determine the latest version (no Internet?).${NC}"
  echo -e "${YELLOW}>> If you are already offline, this script cannot help — the${NC}"
  echo -e "${YELLOW}>> committed x86_64 bundle is your fallback.${NC}"
  exit 1
fi
echo -e "${GREEN}>> Latest release: $VER${NC}"

for a in "${ARCHES[@]}"; do
  url="https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/${VER}/dnscrypt-proxy-linux_${a}-${VER}.tar.gz"
  echo ">> Downloading binary for ${a}..."
  if curl -fsSL "$url" -o "$OFFLINE_DIR/dnscrypt-proxy-linux_${a}.tar.gz"; then
    curl -fsSL "${url}.minisig" -o "$OFFLINE_DIR/dnscrypt-proxy-linux_${a}.tar.gz.minisig" || true
    echo -e "${GREEN}   OK: dnscrypt-proxy-linux_${a}.tar.gz${NC}"
  else
    echo -e "${YELLOW}   Skipped ${a} (download failed).${NC}"
  fi
done

echo ">> Refreshing v3 resolver list..."
curl -fsSL "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md" \
  -o "$OFFLINE_DIR/public-resolvers.md"
curl -fsSL "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md.minisig" \
  -o "$OFFLINE_DIR/public-resolvers.md.minisig"

echo "$VER" > "$OFFLINE_DIR/VERSION"

echo ""
echo -e "${GREEN}>> Done. offline/ is ready for a blackout:${NC}"
ls -la "$OFFLINE_DIR"
