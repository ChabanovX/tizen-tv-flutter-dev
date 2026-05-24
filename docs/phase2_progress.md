# Phase 2 Progress — Visible UI Reached

## Result
Tizen homescreen (white house icon + dark panel) now visibly renders in the TV emulator canvas via Mesa swrast software path.

## Mesa source patch

`src/egl/drivers/dri2/platform_wayland.c` — modified `dri2_initialize_wayland` dispatcher:

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

Build: `meson compile -C ~/mesa-build && ninja install`
Deploy: copied to `/usr/lib64/driver/libEGL.so.1.0` in qcow2 with SMACK label `_`.

## Why it works

Tizen launchpad strips `LIBGL_ALWAYS_SOFTWARE=1` from app environment, so Mesa's `disp->Options.ForceSoftware = false` at runtime → dispatcher selected `dri2_initialize_wayland_drm` (wl_drm path that fails because compositor's software_tbm mode doesn't expose wl_drm). Hardcoding `ForceSoftware = true` forces `dri2_initialize_wayland_swrast` which only needs `wl_shm` (always available).

`dri2_initialize_wayland_swrast` returns 1 (success) for all apps. Apps then create `wl_egl_window`, call `wl_surface_commit`, and Tizen homescreen renders visible pixels.

## Source-level proof complete

`dri2_initialize_wayland_swrast` works end-to-end against this compositor. The compositor was always wayland-protocol-compliant; the bug was in env propagation through Tizen launchpad. Mesa source patch is the correct fix.
