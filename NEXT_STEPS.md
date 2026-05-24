# NEXT_STEPS — Executable queue

## In flight
- [ ] **A1**: Configure guest to capture enlightenment core dumps via Tizen's crash_manager OR /etc/sysctl.d. Boot, let crash, mount, pull dump.

## Queued (in order)
- [ ] **A2**: Analyze core dump with host gdb (using pulled guest libc + enlightenment binary)
- [ ] **A3**: Identify exact failing function + symbol
- [ ] **B1**: Write minimal LD_PRELOAD shim addressing first identified missing symbol
- [ ] **B2**: Test shim; if new failure → repeat at B1 level for next symbol
- [ ] **B3**: When enlightenment runs, check if `/run/.wm_ready` created
- [ ] **C1**: After compositor up — verify wayland_egl evas engine init in next app (probably wrt-loader or volume-app)
- [ ] **C2**: Trace evas → libflutter_tizen path
- [ ] **D1**: When Flutter launches, screenshot canvas to confirm visible UI

## Fallback paths (if A1-A3 impractical)
- [ ] **F1**: gdbserver static binary cross-compile, install in guest, connect from host
- [ ] **F2**: Replace enlightenment with custom binary that catches/logs crash early
- [ ] **F3**: Try Mesa with LLVM + llvmpipe instead of softpipe (better EGL extension coverage)
- [ ] **F4**: Try `MESA_LOG_DEBUG=1` env to get verbose Mesa output
