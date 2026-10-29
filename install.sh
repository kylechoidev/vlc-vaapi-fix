#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"

echo "=========================================================="
echo " VLC VA-API Hardware Acceleration Fix Installer"
echo " For Linux Mint 22, Ubuntu 24.04 (Noble), and derivatives"
echo "=========================================================="

# 1. Check for root / sudo
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: This script requires root privileges to install VLC plugins."
        exit 1
    fi
fi

# 2. Locate VLC plugins directory
VLC_PLUGIN_DIR=""
for candidate in \
    "/usr/lib/x86_64-linux-gnu/vlc/plugins/codec" \
    "/usr/lib64/vlc/plugins/codec" \
    "/usr/lib/vlc/plugins/codec"; do
    if [ -d "$candidate" ]; then
        VLC_PLUGIN_DIR="$candidate"
        break
    fi
done

if [ -z "$VLC_PLUGIN_DIR" ]; then
    echo "Error: Could not find VLC plugins codec directory."
    echo "Please ensure VLC is installed via APT ('sudo apt install vlc')."
    exit 1
fi

VLC_BASE_PLUGIN_DIR="$(dirname "$VLC_PLUGIN_DIR")"

# 3. Check for compiled binaries
if [ ! -f "${BIN_DIR}/libvaapi_plugin.so" ] || [ ! -f "${BIN_DIR}/libvaapi_drm_plugin.so" ]; then
    echo "Precompiled binaries not found in 'bin/'. Attempting to build from source..."
    "${SCRIPT_DIR}/build.sh"
fi

# 4. Install plugins
echo "Installing plugins into ${VLC_PLUGIN_DIR}..."
$SUDO install -m 644 "${BIN_DIR}/libvaapi_plugin.so" "${VLC_PLUGIN_DIR}/"
$SUDO install -m 644 "${BIN_DIR}/libvaapi_drm_plugin.so" "${VLC_PLUGIN_DIR}/"

# 5. Regenerate VLC plugin cache
CACHE_GEN=""
for candidate in \
    "/usr/lib/x86_64-linux-gnu/vlc/vlc-cache-gen" \
    "/usr/lib64/vlc/vlc-cache-gen" \
    "/usr/lib/vlc/vlc-cache-gen"; do
    if [ -x "$candidate" ]; then
        CACHE_GEN="$candidate"
        break
    fi
done

if [ -n "$CACHE_GEN" ]; then
    echo "Updating VLC plugin cache with ${CACHE_GEN}..."
    $SUDO "$CACHE_GEN" "$VLC_BASE_PLUGIN_DIR"
else
    echo "Note: vlc-cache-gen not found; cache will be rebuilt when VLC starts."
fi

# 6. Configure user's vlcrc if present
USER_VLCRC="${HOME}/.config/vlc/vlcrc"
if [ -f "$USER_VLCRC" ]; then
    if ! grep -q "^avcodec-hw=vaapi" "$USER_VLCRC"; then
        echo "Configuring ~/.config/vlc/vlcrc to use hardware decoding (vaapi)..."
        cp "$USER_VLCRC" "${USER_VLCRC}.bak-before-vaapi-fix"
        sed -i 's/^#*avcodec-hw=.*/avcodec-hw=vaapi/' "$USER_VLCRC"
    fi
fi

echo ""
echo "=========================================================="
echo " Installation Complete!"
echo "=========================================================="
echo "Verification:"
vlc -H 2>/dev/null | grep -A1 'avcodec-hw' || true
echo ""
echo "Open VLC -> Preferences (Ctrl+P) -> Input / Codecs."
echo "You will now see 'VA-API video decoder' active!"
