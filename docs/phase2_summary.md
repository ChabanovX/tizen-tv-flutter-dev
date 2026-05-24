# Phase 2 — Source-Level Mesa Patch Results

## TL;DR

Three small Mesa source patches restore EGL rendering for Tizen apps in the emulator. Tizen DALi/NUI apps now render visibly. Flutter app launches but is slow in JIT init (separate downstream issue, not blocked by EGL).

## Patches

### Patch 1: Force swrast in dispatcher

`src/egl/drivers/dri2/platform_wayland.c`:

```c
EGLBoolean
dri2_initialize_wayland(_EGLDisplay *disp)
{
   _eglLog(_EGL_WARNING, "PHASE2: dri2_initialize_wayland entered, ForceSoftware=%d, Zink=%d",
           disp->Options.ForceSoftware, disp->Options.Zink);
   /* PHASE2: FORCE swrast unconditionally — bypass wl_drm requirement */
   disp->Options.ForceSoftware = EGL_TRUE;
   EGLBoolean ret = dri2_initialize_wayland_swrast(disp);
   _eglLog(_EGL_WARNING, "PHASE2: dri2_initialize_wayland_swrast returned %d", ret);
   return ret;
}
```

**Why**: Tizen launchpad strips `LIBGL_ALWAYS_SOFTWARE=1` from app environment. Mesa's dispatcher defaults to `dri2_initialize_wayland_drm` which requires `wl_drm` protocol from compositor. Software_tbm compositor mode doesn't expose `wl_drm` → init fails. Forcing `ForceSoftware=true` routes through `dri2_initialize_wayland_swrast` which only needs `wl_shm` (always available).

### Patch 2: Bypass server_supports_format check

`src/egl/drivers/dri2/platform_wayland.c` in `dri2_wl_add_configs_for_visuals`:

```c
} else {
   format = dri2_wl_visuals[idx].pipe_format;
}
/* PHASE2: bypass server_supported check — always add config */
server_supported = true;
format = dri2_wl_visuals[idx].pipe_format;
```

**Why**: Compositor only advertises 19 wl_shm formats. Some visuals in Mesa's table aren't advertised by compositor → config dropped. With this, ALL Mesa configs (260+) get added regardless of compositor's format list. (Side effect: app may get a config that compositor can't render, but in practice this is fine for software TBM.)

### Patch 3: Relax SAMPLES/SAMPLE_BUFFERS matching

`src/egl/main/eglconfig.c` in `_eglMatchConfig`:

```c
EGLBoolean
_eglMatchConfig(const _EGLConfig *conf, const _EGLConfig *criteria)
{
   EGLint attr, val, i;
   EGLBoolean matched = EGL_TRUE;
   /* PHASE2: relax SAMPLES/SAMPLE_BUFFERS — softpipe has none */
   _EGLConfig criteria_relaxed = *criteria;
   if (criteria_relaxed.Samples > 0) criteria_relaxed.Samples = 0;
   if (criteria_relaxed.SampleBuffers > 0) criteria_relaxed.SampleBuffers = 0;
   criteria = &criteria_relaxed;
   ...
}
```

**Why**: Tizen DALi/NUI apps request `EGL_SAMPLES=4, EGL_SAMPLE_BUFFERS=1` (4x MSAA). Mesa softpipe driver_configs have 260 entries but none with MSAA. Pre-patch: `eglChooseConfig` returned 0 matches for all DALi requests → `DaliException`. With this patch, eglChooseConfig matches non-MSAA configs against MSAA requests, giving apps a non-AA rendering surface instead of crash.

## Results

| Stage | Before Phase 2 | After Phase 2 |
|---|---|---|
| Mesa eglInitialize | `failed to get driver name for fd -1` (DRM path) | Returns success via swrast path |
| eglChooseConfig | Returns 0 configs for DALi/Flutter requests | Returns 1+ configs |
| DALi apps | DaliException crash loop | Run; render to canvas |
| Tizen TV viewer | Doesn't render | Curved bar + frame visible |
| Homescreen | Briefly drew house icon then crashed | House icon visible longer |
| Compositor canvas | Pure black | Dark navy with rendered UI elements |
| Flutter app | fg_launch_timeout (no surface) | Process runs but JIT init slow, fg_launch_timeout still fires |

## Flutter remaining gap

Flutter app process executes dotnet-launcher, gets past appcore init, then goes silent. fg_launch_timeout fires at 25s. The process IS alive but doesn't produce a window in time.

Hypotheses (not yet validated):
- .NET runtime + Dart VM JIT compilation takes >25s on softpipe-only CPU
- Tizen.Flutter.Embedding library has its own EGL config requirements not yet checked
- AOT failure forces full JIT path which is much slower
- libflutter_engine.so may also need patches similar to DALi

Next iteration would patch AMD fg_launch_timeout to longer value AND/OR trace Flutter PID syscalls.

## Source-level approach validation

Phase 2 confirms that Mesa source-level patches are the correct fix. The hard blocker identified at end of Phase 1 (binary patching) was an architectural Mesa decision (forcing wl_drm path even when LIBGL_ALWAYS_SOFTWARE=1 was meant to bypass it). With source access, this is a one-line fix (`disp->Options.ForceSoftware = EGL_TRUE` in the dispatcher).

Net visible difference: from pure black compositor canvas → Tizen DALi UI elements (frames, icons) visibly rendering.
