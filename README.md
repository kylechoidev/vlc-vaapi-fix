# VLC VA-API Hardware Acceleration Fix for Linux Mint 22 & Ubuntu 24.04

[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](LICENSE)
[![Platform: Ubuntu 24.04 | Mint 22](https://img.shields.io/badge/Platform-Ubuntu_24.04_%7C_Linux_Mint_22-orange.svg)](#)
[![Hardware: Intel & AMD VA-API](https://img.shields.io/badge/Hardware-Intel_HD%20%2F%20UHD%20%2F%20Iris%20%7C%20AMD_Radeon-green.svg)](#)

Restore native **VA-API GPU hardware video decoding** (H.264, H.265/HEVC 8-bit & 10-bit, VP9) in VLC Media Player on **Linux Mint 22 (Wilma)** and **Ubuntu 24.04 LTS (Noble Numbat)**.

---

## The Problem

If you run VLC on Ubuntu 24.04 or Linux Mint 22, you may have noticed that playing high-bitrate **H.264 or H.265 (HEVC 10-bit)** video causes:
- 100% CPU usage and roaring laptop fans
- Severe stuttering, skipped frames, and jerky playback
- Desynchronized audio

When you check VLC Preferences (`Ctrl + P` -> **Input / Codecs**), the **Hardware-accelerated decoding** dropdown only offers:
- `Automatic`
- `VDPAU video decoder` (NVIDIA only)
- `Disable`

**There is no VA-API option.**

### Why Did This Happen?
Ubuntu 24.04 ships with **FFmpeg 6.1**, but the stock VLC 3.0.20 source package still relied on an obsolete FFmpeg header (`<libavcodec/vaapi.h>`), which was removed in FFmpeg 5. Because the legacy VA-API plugin failed to build against modern FFmpeg, the upstream Debian/Ubuntu package maintainers simply **disabled the VA-API decoder module altogether**.

On systems with **Intel HD/UHD/Iris Graphics** or **AMD Radeon**, VLC fails VDPAU negotiation and silently falls back to brute-force software CPU decoding. On laptops or low-power CPUs (e.g. dual-core ultrabooks), this completely saturates the CPU.

---

## The Solution

This repository provides the missing **`libvaapi_plugin.so`** and **`libvaapi_drm_plugin.so`** modules:
1. Backported from VLC 3.0.24 (which rewrote the VA-API plugin to use modern FFmpeg 6+ libavcodec APIs).
2. Compiled against Ubuntu's exact `libvlccore9` (3.0.20) and `libavcodec60` (6.1.1) headers to guarantee **100% binary ABI compatibility**.
3. Dropped directly into `/usr/lib/x86_64-linux-gnu/vlc/plugins/codec/`.

---

## Verified Benchmarks

Tested on **Intel Core i7-7600U (2 Cores / 4 Threads)** with **Intel HD Graphics 620**:
*Test file: 1080p 10-Bit HEVC (H.265) @ 60fps*

| Decoder Pipeline | CPU Usage | GPU Hardware Acceleration | Dropped Frames |
| :--- | :---: | :---: | :---: |
| **Stock Ubuntu VLC (Software CPU fallback)** | **53% – 100%** | ❌ None | Frequent Stuttering |
| **With This VA-API Fix** | **~5%** | ✅ Direct `/dev/dri/renderD128` + `iHD_drv_video.so` | **0** (Buttery Smooth) |

---

## Quick Install (Precompiled 64-bit Binaries)

### One-Line Install:
```bash
curl -sSL https://raw.githubusercontent.com/kylechoidev/vlc-vaapi-fix/main/install.sh | bash
```

### Or Manual Clone & Install:
```bash
git clone https://github.com/kylechoidev/vlc-vaapi-fix.git
cd vlc-vaapi-fix
chmod +x install.sh
./install.sh
```

The installer will:
1. Copy `libvaapi_plugin.so` and `libvaapi_drm_plugin.so` to `/usr/lib/x86_64-linux-gnu/vlc/plugins/codec/`.
2. Regenerate VLC's plugin cache with `vlc-cache-gen`.
3. Set `avcodec-hw=vaapi` in your `~/.config/vlc/vlcrc` (saving a backup of your old config).

---

## How to Verify

1. Run VLC's command-line help check:
   ```bash
   vlc -H 2>/dev/null | grep -A1 'avcodec-hw'
   ```
   **Output:**
   ```text
   --avcodec-hw {any,vaapi,vaapi_drm,vdpau_avcodec,none} 
                              Hardware decoding
   ```

2. Open VLC, go to **Tools** -> **Preferences** (`Ctrl + P`) -> **Input / Codecs**:
   - In the **Hardware-accelerated decoding** dropdown, you will now see **`VA-API video decoder`** and **`VA-API video decoder via DRM`**!

3. While playing an H.264/H.265 video, verify active GPU handles:
   ```bash
   lsof -p $(pgrep -n -x vlc) 2>/dev/null | grep -E 'renderD|iHD|amdgpu'
   ```
   You will see VLC actively decoding via `/dev/dri/renderD128` using your Intel/AMD VA-API driver.

---

## Building from Source (Optional)

If you prefer to compile the shared objects yourself from source (takes ~2 seconds):

```bash
# 1. Install build headers
sudo apt-get update && sudo apt-get install -y \
  build-essential pkg-config libva-dev libavcodec-dev libavutil-dev libvlccore-dev

# 2. Run the build script
./build.sh

# 3. Install
./install.sh
```

---

## Uninstallation

To cleanly remove the plugins and revert VLC to its stock state:
```bash
./uninstall.sh
```

---

## License

This project incorporates source components from the VideoLAN VLC media player project and is licensed under the [GNU General Public License v2.0 or later](LICENSE).
