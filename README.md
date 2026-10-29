# VLC VA-API Hardware Acceleration Fix for Linux Mint 22 & Ubuntu 24.04

[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](LICENSE)
[![Platform: Ubuntu 24.04 | Mint 22](https://img.shields.io/badge/Platform-Ubuntu_24.04_%7C_Linux_Mint_22-orange.svg)](#)
[![Hardware: Intel & AMD VA-API](https://img.shields.io/badge/Hardware-Intel_HD%20%2F%20UHD%20%2F%20Iris%20%7C%20AMD_Radeon-green.svg)](#)

Restore native **VA-API GPU hardware video decoding** (H.264, H.265/HEVC 8-bit & 10-bit, VP9) in VLC Media Player on **Linux Mint 22 (Wilma)** and **Ubuntu 24.04 LTS (Noble Numbat)**.

---

## The Symptom

If you run VLC on Ubuntu 24.04 or Linux Mint 22, playing high-bitrate **H.264 or H.265 (HEVC 10-bit)** video causes:
- 100% CPU usage and roaring laptop fans
- Severe stuttering, dropped frames, and jerky playback
- Audio/video desynchronization

When you check VLC Preferences (`Ctrl + P` -> **Input / Codecs**), the **Hardware-accelerated decoding** dropdown only offers:
- `Automatic`
- `VDPAU video decoder` (NVIDIA only)
- `Disable`

**There is no VA-API option.**

---

## Technical Deep-Dive: What Was Broken & How We Fixed It

### 1. What Was Broken in the Code

#### The Deprecated FFmpeg 4 Code in VLC 3.0.20
Historically, VLC 3.0 used FFmpeg’s legacy VA-API acceleration structures in `modules/codec/avcodec/vaapi.c`:
```c
// Legacy FFmpeg 4 API (VLC 3.0.20)
#include <libavcodec/vaapi.h>

struct vaapi_context *hwctx;
hwctx = av_mallocz(sizeof(*hwctx));
hwctx->display    = p_va->p_display;
hwctx->context_id = p_va->context_id;
```

#### The Breaking Change in Ubuntu 24.04 (FFmpeg 6.1)
Ubuntu 24.04 upgraded the system multimedia stack to **FFmpeg 6.1** (`libavcodec60`). FFmpeg 5 and 6 permanently **deleted** `<libavcodec/vaapi.h>` and `struct vaapi_context`. FFmpeg shifted to a unified buffer-pool model based on `AVHWDeviceContext` (`AV_HWDEVICE_TYPE_VAAPI`) and `AVHWFramesContext`:
```text
fatal error: libavcodec/vaapi.h: No such file or directory
   #include <libavcodec/vaapi.h>
            ^~~~~~~~~~~~~~~~~~~~
compilation terminated.
```

#### Why Ubuntu/Debian Shipped Without It
Because stock VLC 3.0.20 would not compile against FFmpeg 6.1 with VA-API enabled, the Debian and Ubuntu package maintainers disabled the VA-API hardware decoder (`--disable-vaapi`) when compiling the official distro packages. 

They left only **VDPAU** (NVIDIA's API). On systems with **Intel HD/UHD/Iris Graphics** or **AMD Radeon**, VDPAU immediately fails to initialize, causing VLC to silently drop back to brute-force CPU software decoding.

---

### 2. How We Fixed It

Rather than forcing users to compile all of VLC from source (a 100MB download requiring dozens of obscure build dependencies), we engineered a surgical, binary-compatible plugin fix:

```
+-----------------------------------------------------------------------------------+
|                              HOW THE FIX WORKS                                    |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  [VLC 3.0.24 Upstream]           [Ubuntu 24.04 / Mint 22 System]                 |
|   Modernized vaapi.c &              libvlccore.so.9 (v3.0.20)                     |
|   vlc_vaapi.c (FFmpeg 6+ API)       libavcodec.so.60 (v6.1.1)                    |
|             \                                    /                                |
|              \                                  /                                 |
|               +---------> [ GCC Compiler ] <---+                                  |
|                                  |                                                |
|                                  v                                                |
|                 +---------------------------------+                               |
|                 |    libvaapi_plugin.so           |                               |
|                 |    libvaapi_drm_plugin.so       |                               |
|                 +---------------------------------+                               |
|                                  |                                                |
|                                  v (Copied into)                                  |
|             /usr/lib/x86_64-linux-gnu/vlc/plugins/codec/                          |
|                                  |                                                |
|                                  v (Re-indexed via)                               |
|                            vlc-cache-gen                                          |
|                                  |                                                |
|                                  v                                                |
|               [ VLC Plays H.265 at ~5% CPU on GPU ASIC! ]                         |
+-----------------------------------------------------------------------------------+
```

#### Step 1: Upstream Porting & ABI Audit
VideoLAN modernized `modules/codec/avcodec/vaapi.c` in VLC 3.0.24 to support FFmpeg's `av_hwdevice_ctx_create` and modern `AVBufferRef`. We extracted these modernized source files and performed an ABI differential analysis against VLC 3.0.20's plugin interface:
- `vlc_va_t` struct layout: **Identical**
- `vlc_va_operations` function table: **Identical**
- `vlc_plugin.h` symbol exports (`vlc_entry__...`): **Identical**

Because the module boundary interface was 100% ABI-identical, a modern VA-API plugin could run seamlessly inside Ubuntu's stock VLC 3.0.20 runtime.

#### Step 2: Minimalist Header Isolation
We isolated the exact headers required (`vaapi.c`, `vlc_vaapi.c`, `va.h`, `avcodec.h`, `vlc_fixups.h`) and created a lightweight `config.h` matching Ubuntu's build flags (`HAVE_AVCODEC_VAAPI`, `HAVE_LIBVA_DRM`, `-DMODULE_NAME_IS_vaapi`, `-D__PLUGIN__`). This eliminates the need for full VLC autotools/cmake build infrastructure.

#### Step 3: Standalone Shared-Library Compilation
We compiled the plugins directly against Ubuntu 24.04's native runtime libraries:
```bash
gcc -shared -O2 -fPIC -std=gnu11 \
  -include src/config.h -Isrc -I/usr/include/vlc/plugins \
  src/modules/codec/avcodec/vaapi.c src/modules/hw/vaapi/vlc_vaapi.c \
  -o bin/libvaapi_plugin.so \
  -lvlccore $(pkg-config --libs libavcodec libavutil libva) -Wl,-z,defs
```
`-Wl,-z,defs` guarantees that all symbols resolve strictly against the host system's `libvlccore.so.9` and `libavcodec.so.60`.

#### Step 4: Dynamic Cache Registration
We install the two compiled `.so` files into `/usr/lib/x86_64-linux-gnu/vlc/plugins/codec/` and execute:
```bash
sudo /usr/lib/x86_64-linux-gnu/vlc/vlc-cache-gen /usr/lib/x86_64-linux-gnu/vlc/plugins
```
This updates VLC's binary descriptor database (`plugins.dat`). When VLC starts, its dynamic module loader discovers `vaapi` and `vaapi_drm` alongside the stock codecs and activates direct Intel/AMD hardware decoding.

---

## Verified Benchmarks

Tested on **Intel Core i7-7600U (2 Cores / 4 Threads)** with **Intel HD Graphics 620**:
*Test file: Better Call Saul S04E06 (1080p 10-Bit HEVC / H.265 @ 60fps)*

| Decoder Pipeline | CPU Usage | GPU Hardware Acceleration | Dropped Frames |
| :--- | :---: | :---: | :---: |
| **Stock Ubuntu VLC (Software CPU fallback)** | **53% – 100%** | ❌ None | Frequent Stuttering |
| **With This VA-API Fix** | **~5%** | ✅ Direct `/dev/dri/renderD128` + `iHD_drv_video.so` | **0** (Buttery Smooth) |

VLC log confirmation:
```text
libva info: VA-API version 1.20.0
libva info: Trying to open /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so
libva info: Found init function __vaDriverInit_1_20
libva info: va_openDriver() returns 0
[avcodec decoder] Using Intel iHD driver for Intel(R) Gen Graphics - 24.1.0 () for hardware decoding
```

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
