#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
BIN_DIR="${SCRIPT_DIR}/bin"

mkdir -p "${BIN_DIR}"

echo "=== Checking build dependencies ==="
MISSING_DEPS=()
for pkg in libva libva-drm libavcodec libavutil; do
    if ! pkg-config --exists "$pkg"; then
        MISSING_DEPS+=("$pkg")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ] || ! command -v gcc >/dev/null 2>&1; then
    echo "Missing build dependencies. Install them with:"
    echo "  sudo apt-get update && sudo apt-get install -y build-essential pkg-config libva-dev libavcodec-dev libavutil-dev libvlccore-dev"
    exit 1
fi

echo "=== Compiling VA-API plugins from source ==="
CF="-O2 -g -fPIC -std=gnu11 -Wall -include ${SRC_DIR}/config.h -I${SRC_DIR} -I/usr/include/vlc/plugins -idirafter ${SRC_DIR}/include -D__PLUGIN__ -DLIBAVFORMAT_VERSION_MICRO=100 -I${SRC_DIR}/modules/codec/avcodec -DMODULE_NAME_IS_vaapi $(pkg-config --cflags libavcodec libavutil libva libva-drm)"
LIBS="/usr/lib/x86_64-linux-gnu/libvlccore.so.9 $(pkg-config --libs libavcodec libavutil libva)"

echo "  -> Building libvaapi_drm_plugin.so..."
gcc -shared ${CF} -DMODULE_STRING=\"vaapi_drm\" -DVLC_VA_BACKEND_DRM \
  "${SRC_DIR}/modules/codec/avcodec/vaapi.c" "${SRC_DIR}/modules/hw/vaapi/vlc_vaapi.c" \
  -o "${BIN_DIR}/libvaapi_drm_plugin.so" ${LIBS} $(pkg-config --libs libva-drm) -Wl,-z,defs

echo "  -> Building libvaapi_plugin.so..."
gcc -shared ${CF} -DMODULE_STRING=\"vaapi\" \
  "${SRC_DIR}/modules/codec/avcodec/vaapi.c" "${SRC_DIR}/modules/hw/vaapi/vlc_vaapi.c" \
  -o "${BIN_DIR}/libvaapi_plugin.so" ${LIBS} -Wl,-z,defs

echo "=== Build Successful! ==="
ls -lh "${BIN_DIR}"/*.so
echo "Run './install.sh' to install the plugins into VLC."
