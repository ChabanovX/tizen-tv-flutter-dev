# Tizen TV Emulator UI rendering on Pop!_OS (Linux x86_64) — design

**Date**: 2026-05-22
**Context**: Continuation of Linux-side investigation (see `docs/FINDINGS.md` iterations 6-7 for prior Linux work and iterations 1-5 for Mac history).

## Goal

See Flutter UI of `hello_tizen_tv` (Material counter app) rendered inside Samsung TV emulator window on Pop!_OS 24.04 Cosmic Wayland. Software rendering acceptable. Slow frame rate (≤5 fps) acceptable. Hot reload not required. Persistent setup acceptable (we modify qcow2 / emulator binary, not require re-flash each session).

## Out of scope

- Hot reload working
- Production frame rate (≥30 fps)
- Hardware-acceleration parity with real TV
- Generic solution for arbitrary Tizen TV emulator versions
- Open-source release of patches (they are project-local)

## Known constraints

- Real Samsung TV hardware not available in any near-term timeframe — emulator is the only viable dev cycle
- Host machine: Pop!_OS 24.04, AMD Ryzen 5 3500, NVIDIA RTX 3050 (working OpenGL 3.2), KVM, 15 GiB RAM
- Tizen Studio 6.1, TV Extension 10.0, kernel 4.4.35-x86_64 inside guest (predates virgl 3D protocol support)
- Samsung-issued certs available from prior Mac iteration; install + AUL launch pipeline already works
- Guest stack: `libEGL.so.1.0` is Samsung VIGS-only, no `/usr/lib64/dri/`, no `virtio_gpu` kernel module
- Maru-x86-machine QEMU machine type does not support `virtio-gpu-pci` device

## Strategy: three approaches in escalation order

Try cheapest first. Stop and document at each gate.

### Approach A — EFL software backend (1–2 days, low risk)

**Hypothesis**: Tizen's evas/EFL layer supports a software backend (`wayland_shm`) alongside the failing `wayland_egl`. Forcing the system-wide engine selection to `wayland_shm` lets EFL apps (including the wrt-loader home-screen processes and enlightenment compositor) render without needing a working `eglGetDisplay()`. Once enlightenment renders, `/tmp/.wm_ready` is created, SMACK denials stop, systemd reaches multi-user.target, the TV home screen appears. Flutter then runs through its own embedder; if it can be coerced into using a Wayland shm buffer for software-rendered Skia output, UI appears in the skin canvas.

**Implementation outline**:
1. Mount qcow2 RW via qemu-nbd, inventory `/usr/lib64/libevas_engines/wayland_shm*` and `/usr/lib64/ecore_evas/engines/`. Confirm shm engine artifacts exist.
2. Add `/etc/profile.d/zz-evas-shm.sh` setting `EVAS_RENDER_ENGINE=wayland_shm` + `ELM_ENGINE=wayland_shm` + `ELM_ACCEL=none`. Also add to relevant systemd units' `Environment=` if profile.d not loaded early enough.
3. Boot emulator, observe `~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog` — expect SMACK denials on `.wm_ready` to stop, expect home screen launcher startup messages.
4. Once home screen renders, run `flutter-tizen run -d emulator-26101 --enable-software-rendering` on host.
5. If Flutter still fails on EGL: disassemble `libflutter_tizen.so` find ecore_wl2/EGL init, attempt binary patch to use shm.

**Validation criterion**: at any iteration step, screenshot host-side `cosmic-screenshot` shows TV home screen or Flutter UI inside emulator skin canvas (currently empty/black).

**Known unknowns**:
- (U-A1) Does `libevas_engine_wayland_shm` exist in this guest qcow2?
- (U-A2) Does Flutter Tizen embedder accept a Wayland shm buffer, or is it hardcoded on EGL?

If U-A1 false → escalate to copying shm engine from another Tizen build OR cross-compile EFL shm engine.
If U-A2 false → binary patch libflutter_tizen.so to skip EGL surface creation.

**Stop condition**: 1.5 days without home-screen render → escalate to Approach B.

### Approach B — deeper binary RE (2–3 days, medium risk)

**Hypothesis**: emulator binary's `maru_qt5_display` system has internal forks beyond what we've found. `qt5_gui_init` at 0x48e810 uses Qt vtable indirection (so r2 didn't catch direct refs to `qt5IsOnscreen` strings inside). Disassembling through these vtables in ghidra finds the actual decision point. Combined with the existing iteration-4 enlightenment patch from Mac (6-byte HWC patch) and onscreen-mode force, emulator pixels become visible in skin canvas.

**Implementation outline**:
1. Install ghidra on host. Load `emulator-x86_64`.
2. Map full call graph of `maru_qt5_display_init → qt5_prepare → qt5_gui_init` and its callees.
3. Identify the function that consumes `qt5IsOnscreen` flag and creates either QOffscreenSurface or onscreen QWindow.
4. Patch to always create onscreen QWindow regardless of flag.
5. Combine with `enlightenment-patched` swap from Mac docs/static-fb-test/.
6. Restart, observe enlightenment reaches MAIN LOOP, check Tizen TV home screen renders to skin canvas.

**Stop condition**: 2 days without progress → escalate to Approach C.

### Approach C — Mesa-virgl + new kernel (1–2 weeks, high risk)

**Hypothesis**: replace the guest GL stack entirely. Build a new Linux kernel ≥4.9 from Samsung Tizen TV kernel sources with `CONFIG_DRM_VIRTIO_GPU=y`. Cross-compile Mesa with virgl driver and Wayland EGL platform for Tizen TV x86_64 glibc ABI. Replace `libEGL.so.1.0` + dependencies in qcow2, install kernel module. Switch QEMU device from `vigs` to `virtio-gpu-gl-pci`. Either patch `maru-x86-machine` to accept virtio-gpu OR pivot to stock QEMU and accept loss of maru-evdi (sdb may need workaround).

**Stop condition**: Samsung kernel sources cannot be located, or Mesa cross-compile against Tizen sysroot fails fundamentally (irreconcilable ABI mismatch).

## FINDINGS continuation strategy

- `docs/FINDINGS.md` keeps existing iterations 1-7 intact (Mac history + initial Linux setup).
- New iterations 8+ append as Linux-only sections, format: `## Iteration N (YYYY-MM-DD, <approach letter> <topic>)`.
- Each iteration captures: hypothesis, what we changed, observed result, decision (continue/escalate/abort).
- Spec doc (this file) referenced as starting point. Plan doc (next, from writing-plans) will track step-by-step actions.

## Risk management

| Risk | Mitigation |
|---|---|
| Patches in qcow2 break boot irrecoverably | Keep `/tmp/enlightenment.orig` backup; commit qemu-img base+overlay snapshot before each modification |
| Binary patches in emulator-x86_64 crash on boot | Keep `emulator-x86_64.orig` backup; revert if startup fails |
| Approach A unknowns burn budget | Strict 1.5-day cap; escalate quickly |
| Approach C kernel build fails partway | Document blockers in FINDINGS, archive intermediate artifacts, decide whether to halt or try kernel modules approach (load virtio_gpu as module via custom initramfs) |
| Cross-contamination of patches | Each approach uses fresh qcow2 (copy from `~/tizen-studio/platforms/tizen-10.0/tv-samsung/emulator-images/...`), separate VM names if needed |
| Tailscale flaps interrupt long-running work | Heartbeat ScheduleWakeups; resume from `docs/FINDINGS.md` state on reconnect |

## Success exit

When skin canvas inside Tizen Emulator window shows visible Flutter counter app pixels (even at 1 fps), screenshot via `cosmic-screenshot`, append final iteration to FINDINGS describing the working configuration, commit qcow2 + patches as artifacts, document reproduction recipe in `docs/start-tizen-emulator.sh` so anyone with this Linux box can boot to working emulator in one command.
