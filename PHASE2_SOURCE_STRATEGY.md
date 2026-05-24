# Phase 2 — Source-Level Strategy

## Mission
Get Flutter `hello_tizen_tv` visibly rendered inside the TV-Samsung-10 emulator.

Phase 1 (binary patching) reached compositor MAIN LOOP and made apps install+launch, but EGL initialization fails because Mesa wayland EGL cannot acquire a usable DRM fd from the software_tbm compositor. Binary-only attack surface fully exhausted.

## Source-level approaches considered

### Approach A — Patch enlightenment compositor

**Goal**: Expose `wl_drm` (or `zwp_linux_dmabuf_v1`) protocol in software_tbm compositor mode so Mesa wayland EGL acquires a usable DRM fd.

| Criterion | Assessment |
|---|---|
| Source availability | Public via `tizen.org` git: `git://review.tizen.org/platform/upstream/enlightenment.git` (Tizen TV-Samsung fork unknown — likely closed). Upstream enlightenment master available; Tizen-specific patches probably not in the public branch. |
| Build toolchain | Tizen platform builds normally via `gbs` (Gentoo-based Tizen Build System) or `scratchbox`. We have native x86_64 cross-toolchain working for Mesa, but enlightenment depends on Tizen-specific patches to ecore/evas/wayland-tbm-server, libtdm, etc. — substantial dependency tree. |
| Blast radius | LARGE — compositor is critical. Bad rebuild → no UI at all. |
| Fastest PoC | ~1–2 days: identify where Tizen's enlightenment patches the software_tbm path to skip wl_drm advertisement, undo that skip OR force the advertise. Then rebuild + replace `/usr/bin/enlightenment` (which we have full control over via qcow2 mount). |
| Risk | Dependencies may need rebuilding too (libwayland-tbm-server, libtdm). Substantial yak shave. |

### Approach B — Patch Mesa Wayland EGL (USER'S PREFERRED FIRST CHOICE)

**Goal**: Make Mesa's `dri2_initialize_wayland_swrast` path succeed against this compositor without requiring wl_drm or DRM fd. Force pure swrast (`DRI_SCREEN_SWRAST`, fd=-1, software softpipe driver).

| Criterion | Assessment |
|---|---|
| Source availability | ✅ Already have full Mesa 26.2.0-devel source at `~/mesa-src` on `popos`. |
| Build toolchain | ✅ Already configured. `meson` + `ninja` at `~/mesa-build`. Cross-builds work; output goes to `~/mesa-install` which we already deploy to guest. |
| Blast radius | SMALL — only replaces `libEGL.so.1.0` in `/usr/lib64/driver/`. Easy revert via qcow2 mount. |
| Fastest PoC | ~1 day: identify exact failure point in Mesa source via instrumented build with verbose logging, then make targeted patch (likely 5–50 LOC). |
| Risk | LOW — Mesa source provides clear dispatcher logic. We've already mapped function offsets from binary. |

### Approach C — Patch flutter-tizen embedder

**Goal**: Add software renderer to libflutter_tizen.so so Flutter doesn't need EGL at all.

| Criterion | Assessment |
|---|---|
| Source availability | Public via `github.com/flutter-tizen/embedder`. We can clone. |
| Build toolchain | Requires `flutter-engine` build environment + GN/Ninja + Dart SDK + Tizen NDK. Substantial setup. |
| Blast radius | SMALL — only Flutter affected, system continues fine. |
| Fastest PoC | ~3–5 days: clone embedder, write new `tizen_renderer_software.cc` mirroring `tizen_renderer_egl.cc` structure but using `FlutterSoftwareRendererConfig` (just `surface_present_callback` returning RGBA buffer to commit via `wl_shm`). Integrate into `FlutterTizenEngine::CreateRenderer()`. Build, replace `/opt/usr/dotnet/Libraries/libflutter_tizen.so..*`. |
| Risk | Flutter engine GN/BUILD knowledge ramp. Doesn't solve EGL for other Tizen apps (CSFS, volume, tv-viewer still broken). |

## Ranking

| Approach | Feasibility | Source | Toolchain | Blast | PoC speed | Score |
|---|---|---|---|---|---|---|
| **B (Mesa)** | ✅ best | ✅ have | ✅ have | small | fastest | **WINNER** |
| A (compositor) | 🟡 medium | partial | hard | large | medium | 2nd |
| C (Flutter embedder) | 🟡 medium | ✅ public | hard setup | small | slow | 3rd |

## Chosen path: Approach B — Mesa source patch

### Why
1. Source + toolchain already in place from iter18's cross-build
2. Smallest blast radius — only libEGL.so.1.0
3. We already know the Mesa code path from disassembly (function names, offsets)
4. **The fix may be tiny**: Mesa already has `dri2_initialize_wayland_swrast` (pure-software path needing only `wl_shm`). The dispatcher selects it via `disp->Options.ForceSoftware`, which is set from `LIBGL_ALWAYS_SOFTWARE=1` env (which we already set). Yet binary execution still hits the wl_drm path. The Phase 2 task is to identify WHY and either:
   - Fix the env propagation (might be a missing piece in the build config)
   - OR force `ForceSoftware = true` unconditionally inside the dispatcher
5. If this approach reveals the fix is impossible (Mesa-side architectural block), we document it and pivot to Approach A.

### Smallest possible proof-of-concept

Steps:

1. **Instrument current Mesa build** — add `_eglLog(_EGL_WARNING, "dri2_initialize_wayland: ForceSoftware=%d", disp->Options.ForceSoftware)` at the top of `dri2_initialize_wayland`. Rebuild, deploy, boot, observe what value is actually seen at runtime.
2. **Trace which init path** runs (`_swrast` vs `_drm`). Add a similar log.
3. **If ForceSoftware=0 at runtime** — env propagation problem. Fix env or hardcode `ForceSoftware=1` for wayland platform. Smallest patch: one-line `disp->Options.ForceSoftware = true;` in dri2_initialize_wayland.
4. **If ForceSoftware=1 but DRM path still runs** — dispatcher bug, hardcode call to `_swrast`. Smallest patch: replace the if/else in dri2_initialize_wayland with unconditional `return dri2_initialize_wayland_swrast(disp);`.
5. **If swrast path runs but still fails** — trace which call fails. Likely candidates: wl_shm bind, dri2_create_screen, dri2_setup_device. Each has identifiable error logging.
6. **If swrast path requires something compositor doesn't have** — document with exact source reference, then pivot to Approach A.

### Stop conditions for Approach B

- Mesa source already provides the swrast code path → no architectural block exists; iterate until working OR until the actual missing piece in compositor is precisely identified.
- Only stop if rebuild fails for environment reasons, or if Mesa source genuinely lacks a wl_drm-free path (we've confirmed it doesn't — the code exists).
