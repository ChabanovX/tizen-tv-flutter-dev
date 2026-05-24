# Phase 3 — Active Queue

## Now
- [ ] **B1**: Build a process introspection probe service that polls /proc/<pid>/* for the Flutter PID every 2s and writes to SMACK-friendly path (`/home/owner/share/tmp/sdk_tools/flutter_probe.log`). Boot, let probe accumulate ~120s of data, mount qcow2 and pull log.

## Queued
- [ ] **B2**: Identify thread states (R/S/D/Z), wchan values per thread — distinguishes CPU-bound vs blocked.
- [ ] **B3**: Diff between live DALi-rendering app (e.g. csfs once it stabilizes) and Flutter process — same instrumentation, same boot.
- [ ] **B4**: Identify whether libflutter_engine.so is dlopen'd or stuck loading.
- [ ] **B5**: If process is blocked in futex — find the lock holder, the contending thread.
- [ ] **B6**: Add strace via run-script patched into dotnet-launcher invocation (if probe insufficient).

## Phase 3 fallback paths (if probe path blocked)
- [ ] **F1**: Build a static gdbserver and inject into Flutter app
- [ ] **F2**: Patch libdotnet_launcher_core.so to log every major init step
- [ ] **F3**: Build a minimal Flutter app variant with profile/release mode to test H1
- [ ] **F4**: Patch libflutter_tizen.so to log earliest init step
