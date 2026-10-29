#!/usr/bin/env bash
set -e

echo "=========================================================="
echo " VLC VA-API Hardware Acceleration Fix Uninstaller"
echo "=========================================================="

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: This script requires root privileges to remove VLC plugins."
        exit 1
    fi
fi

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

if [ -n "$VLC_PLUGIN_DIR" ]; then
    echo "Removing VA-API plugins from ${VLC_PLUGIN_DIR}..."
    $SUDO rm -f "${VLC_PLUGIN_DIR}/libvaapi_plugin.so" "${VLC_PLUGIN_DIR}/libvaapi_drm_plugin.so"
    
    VLC_BASE_PLUGIN_DIR="$(dirname "$VLC_PLUGIN_DIR")"
    CACHE_GEN="$(which vlc-cache-gen 2>/dev/null || echo "/usr/lib/x86_64-linux-gnu/vlc/vlc-cache-gen")"
    if [ -x "$CACHE_GEN" ]; then
        echo "Updating VLC plugin cache..."
        $SUDO "$CACHE_GEN" "$VLC_BASE_PLUGIN_DIR"
    fi
fi

USER_VLCRC="${HOME}/.config/vlc/vlcrc"
if [ -f "${USER_VLCRC}.bak-before-vaapi-fix" ]; then
    echo "Restoring previous ~/.config/vlc/vlcrc configuration..."
    mv "${USER_VLCRC}.bak-before-vaapi-fix" "$USER_VLCRC"
fi

echo "Uninstallation complete. VLC reverted to stock configuration."
