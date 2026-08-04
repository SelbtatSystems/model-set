#!/usr/bin/env bash
# Update Claude Code (native install) without the built-in updater's download deadline.
#
# `claude update` aborts the download after a fixed deadline. The binary is ~275 MB,
# so on a slow link (VPN, hotel wifi, throttled ISP) it never finishes and leaves a
# 0-byte placeholder in versions/ plus a "Auto-update failed" banner. This does the
# same job with resume + retries and no total deadline, and verifies the SHA-256 from
# Anthropic's release manifest before installing anything.
#
# Usage: claude-update.sh [version]     (default: latest for the release channel)
set -euo pipefail

BASE_URL="https://downloads.claude.ai/claude-code-releases"
VERSIONS_DIR="$HOME/.local/share/claude/versions"
LAUNCHER="$HOME/.local/bin/claude"

# Give up only if the transfer stalls under 1 KB/s for 10 minutes straight — slow is
# fine, dead is not. No --max-time: a 275 MB file over a VPN legitimately takes hours.
CURL_OPTS=(--fail --location --continue-at - --retry 20 --retry-delay 10
           --retry-all-errors --speed-limit 1024 --speed-time 600)

die() { echo "claude-update: $*" >&2; exit 1; }

detect_platform() {
    local os arch libc=""
    case "$(uname -s)" in
        Linux)  os=linux ;;
        Darwin) os=darwin ;;
        *)      die "unsupported OS: $(uname -s)" ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)  arch=x64 ;;
        aarch64|arm64) arch=arm64 ;;
        *)             die "unsupported architecture: $(uname -m)" ;;
    esac
    # musl builds are a separate artifact; glibc systems must not get them.
    if [ "$os" = linux ] && ! ldd --version 2>&1 | grep -qi glibc; then
        libc="-musl"
    fi
    echo "${os}-${arch}${libc}"
}

PLATFORM="$(detect_platform)"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(curl -fsSL --max-time 30 "$BASE_URL/latest")" \
        || die "could not reach the release channel — check your connection"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "not a version string: $VERSION"

INSTALLED=""
[ -x "$LAUNCHER" ] && INSTALLED="$("$LAUNCHER" --version 2>/dev/null | awk '{print $1}')"
if [ "$INSTALLED" = "$VERSION" ]; then
    echo "claude-update: already on $VERSION"
    exit 0
fi
echo "claude-update: $PLATFORM  ${INSTALLED:-none} -> $VERSION"

echo "[1/4] reading release manifest..."
MANIFEST="$(curl -fsSL --max-time 60 "$BASE_URL/$VERSION/manifest.json")" \
    || die "no manifest for $VERSION"
read -r BINARY CHECKSUM SIZE <<<"$(
    printf '%s' "$MANIFEST" |
    jq -r --arg p "$PLATFORM" '.platforms[$p] | "\(.binary) \(.checksum) \(.size)"'
)"
[ -n "${CHECKSUM:-}" ] && [ "$CHECKSUM" != null ] || die "manifest has no $PLATFORM build"

mkdir -p "$VERSIONS_DIR" "$(dirname "$LAUNCHER")"
cd "$VERSIONS_DIR"
# A previous failed run leaves a 0-byte file at the final path; resume uses .part only.
[ -s "$VERSION" ] || rm -f "$VERSION"

echo "[2/4] downloading $VERSION ($SIZE bytes, resumable)..."
curl "${CURL_OPTS[@]}" -o "$VERSION.part" "$BASE_URL/$VERSION/$PLATFORM/$BINARY"

echo "[3/4] verifying SHA-256..."
echo "$CHECKSUM  $VERSION.part" | sha256sum -c - \
    || { rm -f "$VERSION.part"; die "checksum mismatch — nothing installed"; }

echo "[4/4] installing..."
chmod +x "$VERSION.part"
mv "$VERSION.part" "$VERSION"
ln -sfn "$VERSIONS_DIR/$VERSION" "$LAUNCHER"

echo "claude-update: done — $("$LAUNCHER" --version)"
echo "  rollback: ln -sfn $VERSIONS_DIR/<old-version> $LAUNCHER"
