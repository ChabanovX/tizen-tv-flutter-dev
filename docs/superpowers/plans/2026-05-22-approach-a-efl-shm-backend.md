# Approach A — EFL software backend implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Samsung TV emulator boot fully and render Tizen home screen + Flutter UI by forcing EFL/evas to use `wayland_shm` (software) backend instead of `wayland_egl` (which fails on `eglGetDisplay()` because guest libEGL is VIGS-only).

**Architecture:** Mount the emulator's qcow2 overlay RW via qemu-nbd. Verify a software EFL engine (`evas_engine_wayland_shm`) exists in the guest. Inject system-wide env vars (`EVAS_RENDER_ENGINE=wayland_shm`, `ELM_ENGINE=wayland_shm`, `ELM_ACCEL=none`) so every EFL app — including the wrt-loader home-screen processes and enlightenment compositor — chooses software composition. Once enlightenment runs, it creates `/tmp/.wm_ready`, systemd reaches its WM-ready target, the TV home screen renders into the VIGS-passthrough buffer that the emulator skin canvas shows. Then `flutter-tizen run -d emulator-26101 --enable-software-rendering` installs the TPK and the embedder renders Skia output into a Wayland shm buffer.

**Tech Stack:** ssh to Pop!_OS box (`popos`), `qemu-nbd` for qcow2 mounts, `cosmic-screenshot` for observing the emulator output, `flutter-tizen` for app deployment, Samsung's `tizen` CLI for signing/launching. Spec reference: `docs/superpowers/specs/2026-05-22-tizen-emulator-ui-linux-design.md`.

---

## File Structure

**Host (Mac, where this repo lives):**
- Modify: `docs/FINDINGS.md` (append iteration 8 sections per task)
- Reference: `docs/superpowers/specs/2026-05-22-tizen-emulator-ui-linux-design.md`

**Linux box (popos, via SSH):**
- Read/modify: `~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64` (qcow2 overlay; mount via /dev/nbd0)
- Read: `~/tizen-studio/platforms/tizen-10.0/tv-samsung/emulator-images/tv-samsung-10.0-x86_64/emulimg-10.0.x86_64` (base qcow2 — read-only for safety)
- Read/modify inside mounted guest (`/tmp/tizen-rw/`):
  - Create: `/etc/profile.d/zz-evas-shm.sh`
  - Modify or override: `/etc/systemd/system/user@.service.d/evas-shm.conf` (drop-in)
  - Read: `/usr/lib64/ecore_evas/engines/` and `/usr/lib64/libevas_engine*` to confirm shm artifact presence
- Logs to observe: `~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog` and `emulator.log`

---

## Task 0: Sync FINDINGS between Mac and Linux, open iteration 8

**Files:**
- Pull: `popos:~/development/hello_tizen_tv/docs/FINDINGS.md` → `/Users/chabanovz/work/hello_tizen_tv/docs/FINDINGS.md`
- Modify: `docs/FINDINGS.md` (append iteration 8 header)

- [ ] **Step 1: Pull Linux FINDINGS to Mac**

Run:
```bash
scp popos:/home/vld/development/hello_tizen_tv/docs/FINDINGS.md /tmp/findings-linux.md
wc -l /tmp/findings-linux.md  # expect ~1735 lines
mv /tmp/findings-linux.md /Users/chabanovz/work/hello_tizen_tv/docs/FINDINGS.md
wc -l /Users/chabanovz/work/hello_tizen_tv/docs/FINDINGS.md
```
Expected: file replaced, line count matches Linux side.

- [ ] **Step 2: Append iteration 8 header to Mac FINDINGS**

Append to `docs/FINDINGS.md`:
```markdown

---

## Iteration 8 (2026-05-22, Linux Approach A — EFL software backend)

Spec: `docs/superpowers/specs/2026-05-22-tizen-emulator-ui-linux-design.md`.
Plan: `docs/superpowers/plans/2026-05-22-approach-a-efl-shm-backend.md`.

Hypothesis: forcing `EVAS_RENDER_ENGINE=wayland_shm` system-wide lets EFL apps render without `eglGetDisplay()`, which unblocks enlightenment → `.wm_ready` → boot completion → TV home screen rendering.
```

- [ ] **Step 3: Push synced FINDINGS to Linux**

Run:
```bash
scp /Users/chabanovz/work/hello_tizen_tv/docs/FINDINGS.md popos:/home/vld/development/hello_tizen_tv/docs/FINDINGS.md
ssh popos 'wc -l /home/vld/development/hello_tizen_tv/docs/FINDINGS.md'
```
Expected: line count matches Mac side.

- [ ] **Step 4: Commit on Mac**

Run:
```bash
cd /Users/chabanovz/work/hello_tizen_tv
git add docs/FINDINGS.md docs/superpowers/specs/2026-05-22-tizen-emulator-ui-linux-design.md docs/superpowers/plans/2026-05-22-approach-a-efl-shm-backend.md
git commit -m "docs(emulator): iter8 — Approach A (EFL shm backend) — design + plan + open iteration"
```
Expected: clean commit with three new/modified files.

---

## Task 1: Inventory EFL software-engine artifacts in guest qcow2

**Files:**
- Read inside `/tmp/tizen-rw/` after mount: `/usr/lib64/ecore_evas/engines/`, `/usr/lib64/libevas_engine_wayland_shm*`, `/etc/tizen-platform.conf` (if exists)

- [ ] **Step 1: Kill any running emulator + connect qcow2 overlay via qemu-nbd**

Run:
```bash
ssh popos 'pgrep -x emulator-x86_64 | xargs -r kill -9 ; sleep 2
sudo qemu-nbd -d /dev/nbd0 2>/dev/null
sudo modprobe nbd max_part=8
sudo qemu-nbd -c /dev/nbd0 ~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64
sleep 2
sudo partprobe /dev/nbd0
mkdir -p /tmp/tizen-rw
sudo mount /dev/nbd0p1 /tmp/tizen-rw
ls /tmp/tizen-rw/ | head -5'
```
Expected: top-level guest dirs visible (`bin`, `boot`, `etc`, `usr`, ...).

- [ ] **Step 2: Look for evas wayland_shm engine library**

Run:
```bash
ssh popos 'sudo find /tmp/tizen-rw -name "libevas_engine_wayland*" 2>/dev/null
sudo find /tmp/tizen-rw -name "*wayland_shm*" 2>/dev/null
sudo find /tmp/tizen-rw -name "*wayland_egl*" 2>/dev/null'
```
Expected: at least one of:
- `/tmp/tizen-rw/usr/lib64/evas/modules/engines/wayland_shm/<arch>/module.so`
- `/tmp/tizen-rw/usr/lib64/libevas_engine_wayland_shm.so*`

If only `wayland_egl` exists and no `wayland_shm` anywhere — gate Task 1 fails. Document in FINDINGS, escalate to Approach B.

- [ ] **Step 3: Inspect ecore_evas wayland engine plugin layout**

Run:
```bash
ssh popos 'sudo ls -la /tmp/tizen-rw/usr/lib64/ecore_evas/engines/ 2>/dev/null
sudo ls -la /tmp/tizen-rw/usr/lib64/evas/modules/engines/ 2>/dev/null'
```
Expected: list of subdirectories (`wayland`, `tbm`, possibly `wayland_shm`, `wayland_egl`).

- [ ] **Step 4: Search for EFL environment var docs inside guest**

Run:
```bash
ssh popos 'sudo grep -rE "EVAS_RENDER_ENGINE|ELM_ENGINE|ELM_ACCEL" /tmp/tizen-rw/etc/ /tmp/tizen-rw/usr/lib/systemd/ 2>/dev/null | head -20'
```
Expected: at least references to the variable names if the platform supports them. If empty, env var may not be honored — note in FINDINGS.

- [ ] **Step 5: Unmount, append findings to FINDINGS.md**

Run:
```bash
ssh popos 'sudo umount /tmp/tizen-rw ; sudo qemu-nbd -d /dev/nbd0'
```

Then append to `docs/FINDINGS.md` on Mac:
```markdown

### Task 1 result — guest EFL engine inventory

- evas wayland_shm: <FOUND at /path | NOT FOUND>
- evas wayland_egl: <FOUND at /path>
- ecore_evas engines: <list>
- env-var refs in guest /etc: <count, paths>

Decision: <continue to Task 2 | gate-fail, escalate to Approach B>.
```

Fill in the angle-bracket placeholders with what step 2/3/4 returned. Commit FINDINGS update.

- [ ] **Step 6: Commit**

Run:
```bash
cd /Users/chabanovz/work/hello_tizen_tv
git add docs/FINDINGS.md
git commit -m "docs(emulator): iter8 task1 — guest EFL engine inventory"
scp docs/FINDINGS.md popos:/home/vld/development/hello_tizen_tv/docs/FINDINGS.md
```

---

## Task 2: Inject system-wide EFL software-backend env vars into qcow2

**Gate:** Task 1 step 5 decided "continue". If "escalate" — skip to Approach B plan.

**Files:**
- Create inside guest: `/tmp/tizen-rw/etc/profile.d/zz-evas-shm.sh`
- Create inside guest: `/tmp/tizen-rw/etc/systemd/system/user@.service.d/evas-shm.conf` (drop-in for user systemd)
- Modify inside guest: `/tmp/tizen-rw/etc/systemd/system/multi-user.target.wants/*.service` IF profile.d unreachable

- [ ] **Step 1: Mount qcow2 RW**

Run (same as Task 1 step 1, fresh mount):
```bash
ssh popos 'pgrep -x emulator-x86_64 | xargs -r kill -9 ; sleep 2
sudo qemu-nbd -d /dev/nbd0 2>/dev/null
sudo qemu-nbd -c /dev/nbd0 ~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64
sleep 2
sudo partprobe /dev/nbd0
sudo mount /dev/nbd0p1 /tmp/tizen-rw
ls /tmp/tizen-rw/etc/profile.d/ | head -5'
```
Expected: existing `profile.d` entries listed.

- [ ] **Step 2: Write the env-var profile script**

Run:
```bash
ssh popos 'sudo tee /tmp/tizen-rw/etc/profile.d/zz-evas-shm.sh > /dev/null << "PROFILE_EOF"
# Force EFL/evas to use software (wayland_shm) backend
# Reason: guest libEGL.so.1.0 is VIGS-only; eglGetDisplay() fails.
# See docs/superpowers/specs/2026-05-22-tizen-emulator-ui-linux-design.md
export EVAS_RENDER_ENGINE=wayland_shm
export ELM_ENGINE=wayland_shm
export ELM_ACCEL=none
export EVAS_GL_DISABLE=1
PROFILE_EOF
sudo chmod 0644 /tmp/tizen-rw/etc/profile.d/zz-evas-shm.sh
sudo cat /tmp/tizen-rw/etc/profile.d/zz-evas-shm.sh'
```
Expected: the file written; cat shows the env-var lines.

- [ ] **Step 3: Write systemd env drop-in (covers services that ignore profile.d)**

Run:
```bash
ssh popos 'sudo mkdir -p /tmp/tizen-rw/etc/systemd/system/user@.service.d
sudo tee /tmp/tizen-rw/etc/systemd/system/user@.service.d/evas-shm.conf > /dev/null << "UNIT_EOF"
[Service]
Environment="EVAS_RENDER_ENGINE=wayland_shm"
Environment="ELM_ENGINE=wayland_shm"
Environment="ELM_ACCEL=none"
Environment="EVAS_GL_DISABLE=1"
UNIT_EOF
sudo cat /tmp/tizen-rw/etc/systemd/system/user@.service.d/evas-shm.conf'
```
Expected: file written with `[Service]` + 4 Environment lines.

- [ ] **Step 4: Add the same env to system-level default**

Run:
```bash
ssh popos 'sudo mkdir -p /tmp/tizen-rw/etc/systemd/system.conf.d
sudo tee /tmp/tizen-rw/etc/systemd/system.conf.d/evas-shm.conf > /dev/null << "SYS_EOF"
[Manager]
DefaultEnvironment="EVAS_RENDER_ENGINE=wayland_shm" "ELM_ENGINE=wayland_shm" "ELM_ACCEL=none" "EVAS_GL_DISABLE=1"
SYS_EOF
sudo cat /tmp/tizen-rw/etc/systemd/system.conf.d/evas-shm.conf'
```
Expected: file written, all four vars in DefaultEnvironment.

- [ ] **Step 5: Unmount cleanly**

Run:
```bash
ssh popos 'sync ; sudo umount /tmp/tizen-rw ; sudo qemu-nbd -d /dev/nbd0'
```
Expected: clean unmount, nbd device released.

- [ ] **Step 6: Commit progress to FINDINGS**

Append to `docs/FINDINGS.md`:
```markdown

### Task 2 result — env vars injected into qcow2

Wrote three files inside guest:
- `/etc/profile.d/zz-evas-shm.sh` (for login shells)
- `/etc/systemd/system/user@.service.d/evas-shm.conf` (user systemd services)
- `/etc/systemd/system.conf.d/evas-shm.conf` (system manager default env)

All four vars set: EVAS_RENDER_ENGINE=wayland_shm, ELM_ENGINE=wayland_shm, ELM_ACCEL=none, EVAS_GL_DISABLE=1.
```

Then:
```bash
cd /Users/chabanovz/work/hello_tizen_tv
git add docs/FINDINGS.md
git commit -m "docs(emulator): iter8 task2 — inject EFL shm env vars into guest qcow2"
scp docs/FINDINGS.md popos:/home/vld/development/hello_tizen_tv/docs/FINDINGS.md
```

---

## Task 3: Boot emulator and observe whether wm_ready unlocks

**Files:**
- Reuse: `/tmp/run_tv_no_tuner.sh` (already on Linux box from iter6/7)
- Read: `~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog` (kernel log inside guest)
- Read: `~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.log` (host-side emulator log)

- [ ] **Step 1: Confirm vm_launch.conf still has no-tuner patches and backend=gl**

Run:
```bash
ssh popos 'grep -E "vigs|^-device maru-virtual-tuner|^-device maru-external-input-pci" /tmp/hello_tv_no_tuner.conf | head -5'
```
Expected:
- `-device vigs,backend=gl`
- `#-device maru-virtual-tuner,...` (commented)
- `#-device maru-external-input-pci,...` (commented)

If not — re-apply patches per `/tmp/run_tv_no_tuner.sh` documented behavior.

- [ ] **Step 2: Launch emulator in background**

Run:
```bash
ssh popos 'nohup /tmp/run_tv_no_tuner.sh > /tmp/em-iter8-task3.log 2>&1 < /dev/null & disown
echo "launched"'
```
Expected: "launched".

- [ ] **Step 3: Wait for boot to reach sdb registration**

Run:
```bash
ssh popos 'until ~/tizen-studio/tools/sdb devices 2>&1 | grep -q "emulator-.*device"; do sleep 3; done ; echo READY ; ~/tizen-studio/tools/sdb devices'
```
Expected: emulator-26101 device hello_tv (within ~30s).

- [ ] **Step 4: Count SMACK wm_ready denials over a 30s window**

Run:
```bash
ssh popos 'sleep 30 ; grep -c "denied.*wm_ready" ~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog'
```
Expected: ideally 0 (boot completed), worst case still many (env vars not honored).

Baseline reference: prior iteration showed 32 denials in 30s. Anything below 10 = significant improvement.

- [ ] **Step 5: Check for enlightenment process inside guest via klog**

Run:
```bash
ssh popos 'grep -iE "enlightenment|MAIN LOOP|wayland_shm|wayland_egl|eglGetDisplay" ~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog | tail -30'
```
Expected (success case): one of:
- `enlightenment ... MAIN LOOP`
- Reduced or absent `evas-wayland_egl ... eglGetDisplay() fail`
- New mentions of `wayland_shm`

Capture the actual lines for FINDINGS.

- [ ] **Step 6: Screenshot the Tizen Emulator window**

Run:
```bash
ssh popos 'export DISPLAY=:1 XAUTHORITY=/home/vld/.Xauthority WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000
cosmic-screenshot --interactive=false --notify=false -s /tmp/shots/ 2>&1
ls -t /tmp/shots/ | head -1'
LATEST=$(ssh popos 'ls -t /tmp/shots/ | head -1')
scp "popos:/tmp/shots/$LATEST" /tmp/shots-popos/iter8-task3.png
```
Then view via Read tool: `/tmp/shots-popos/iter8-task3.png`.

Expected (success): TV home screen pixels visible inside skin canvas (currently this area is solid black).

- [ ] **Step 7: Decide gate**

Three possible outcomes:

(a) Home screen visible → continue to Task 4 (Flutter run).
(b) wm_ready denials dropped but skin canvas still black → continue to Task 4 but expect Flutter UI may also not show; gather data.
(c) wm_ready denials unchanged → env vars not honored. Continue to Task 5 (deeper fallback within Approach A).

Document the chosen path in FINDINGS.

- [ ] **Step 8: Append to FINDINGS, commit**

Append to `docs/FINDINGS.md` Iteration 8:
```markdown

### Task 3 result — boot observation with shm env vars

- sdb device state: <"device" | timeout>
- SMACK .wm_ready denials over 30s: <count, baseline was 32>
- New klog signals: <paste relevant lines>
- Screenshot: docs/static-fb-test/iter8-task3.png (TV canvas: <black | home screen | other>)

Decision: <Task 4 / Task 5>.
```

Then commit + sync FINDINGS to Linux as in prior tasks.

---

## Task 4: Install + launch Flutter app with software rendering

**Gate:** Task 3 step 7 chose (a) or (b).

**Files:**
- Run on host: `~/development/hello_tizen_tv/` (existing project on Linux)
- Output: `/tmp/em-iter8-task4-flutter.log`, screenshot `iter8-task4.png`

- [ ] **Step 1: Ensure flutter-tizen + tizen CLI on PATH**

Run:
```bash
ssh popos 'export PATH=$HOME/development/flutter-tizen/bin:$HOME/development/flutter/bin:$HOME/tizen-studio/tools:$HOME/tizen-studio/tools/ide/bin:$PATH
flutter-tizen --version 2>&1 | head -3
~/tizen-studio/tools/sdb devices'
```
Expected: flutter-tizen version printed, emulator-26101 in device list.

- [ ] **Step 2: Run with software rendering, capture output**

Run:
```bash
ssh popos 'cd ~/development/hello_tizen_tv && export PATH=$HOME/development/flutter-tizen/bin:$HOME/development/flutter/bin:$HOME/tizen-studio/tools:$HOME/tizen-studio/tools/ide/bin:$PATH
timeout 240 flutter-tizen run -d emulator-26101 --enable-software-rendering 2>&1 | tail -40' > /tmp/em-iter8-task4-flutter.log 2>&1 &
```

Then wait for completion (~3 minutes).

- [ ] **Step 3: Inspect Flutter logs**

Run:
```bash
cat /tmp/em-iter8-task4-flutter.log | grep -vE "^#|asynchronous" | tail -30
```
Expected: `Built ... .tpk`, `Installing ... pkgcmd install completes`, then either:
- `application is successfully launched. pid = <N>` (good)
- `Connecting to the device logger is taking longer than expected...` (typical)
- Error about EGL or other

Capture verbatim.

- [ ] **Step 4: Check guest klog for Flutter / dotnet process activity**

Run:
```bash
ssh popos 'grep -iE "hello_tizen|dotnet|flutter|Runner.dll|eglGetDisplay" ~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog | tail -20'
```
Expected: dotnet runtime starting messages; absence of fresh `eglGetDisplay() fail` lines after Flutter PID started.

- [ ] **Step 5: Screenshot Tizen Emulator window**

Run:
```bash
ssh popos 'export WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000
cosmic-screenshot --interactive=false --notify=false -s /tmp/shots/'
LATEST=$(ssh popos 'ls -t /tmp/shots/ | head -1')
scp "popos:/tmp/shots/$LATEST" /tmp/shots-popos/iter8-task4.png
```

Then view via Read tool. Look for **counter app UI** (`+` button, "0" text, app bar).

- [ ] **Step 6: Decide gate**

(a) Counter UI visible → **WIN**. Skip to Task 7.
(b) Boot completed, Flutter PID alive, skin canvas still black → flutter embedder hardcoded EGL. Continue to Task 6.
(c) Flutter crashes on launch → check klog for crash signature; likely EGL-related, continue to Task 6.

- [ ] **Step 7: Append + commit**

Append to FINDINGS Iteration 8:
```markdown

### Task 4 result — Flutter launch with --enable-software-rendering

- flutter-tizen run exit: <success | timeout | crash>
- Flutter PID on guest: <N | n/a>
- Fresh eglGetDisplay fails after Flutter started: <count>
- Screenshot: docs/static-fb-test/iter8-task4.png — <UI visible | still black | other>

Decision: <Task 7 success | Task 6 escalation within A>.
```

Commit + sync.

---

## Task 5 (alternate-path branch): env vars not honored — investigate engine loading

**Gate:** Task 3 step 7 chose (c).

**Files:**
- Read guest: `/etc/tizen-platform.conf`, `/etc/profile`, `/etc/environment`, `/etc/systemd/system.conf`
- Read guest: enlightenment binary's hardcoded engine string (strings on `/usr/bin/enlightenment`)

- [ ] **Step 1: Re-mount qcow2 RW, look at how the existing config selects engines**

Run:
```bash
ssh popos 'sudo qemu-nbd -c /dev/nbd0 ~/tizen-studio-data/emulator/vms/hello_tv/emulimg-hello_tv.x86_64
sleep 2 ; sudo partprobe /dev/nbd0 ; sudo mount /dev/nbd0p1 /tmp/tizen-rw
sudo grep -rE "EVAS_RENDER_ENGINE|ELM_ENGINE|ELM_ACCEL|wayland_egl|engine_name" /tmp/tizen-rw/etc/ 2>/dev/null | head -20'
```
Expected: existing references. If a config file hardcodes `wayland_egl`, that's what to patch.

- [ ] **Step 2: Inspect enlightenment binary for engine selection logic**

Run:
```bash
ssh popos 'sudo cp /tmp/tizen-rw/usr/bin/enlightenment /tmp/enlightenment-guest
strings /tmp/enlightenment-guest | grep -iE "EVAS_ENGINE|ELM_ENGINE|wayland_egl|wayland_shm|render_engine" | head -20'
```
Expected: env var names checked, engine name strings. Identifies which env var enlightenment actually reads.

- [ ] **Step 3: Patch the right env var system-wide based on findings**

If e.g. only `EVAS_ENGINE` (not `EVAS_RENDER_ENGINE`) is what enlightenment reads — overwrite the drop-in:

Run:
```bash
ssh popos 'sudo tee /tmp/tizen-rw/etc/profile.d/zz-evas-shm.sh > /dev/null << "PROFILE_EOF"
# Fixed per Task 5 step 2 — actual var enlightenment honors
export EVAS_ENGINE=wayland_shm
export EVAS_RENDER_ENGINE=wayland_shm
export ELM_ENGINE=wayland_shm
export ELM_ACCEL=none
export EVAS_GL_DISABLE=1
PROFILE_EOF
sudo umount /tmp/tizen-rw ; sudo qemu-nbd -d /dev/nbd0'
```

- [ ] **Step 4: Re-run Task 3 steps 2-6**

Loop back to Task 3 step 2 with the new patched env vars. If wm_ready denials drop now → continue to Task 4.

- [ ] **Step 5: If still stuck — escalate**

If after one re-patch cycle the SMACK denials haven't dropped, document and escalate to Approach B (binary RE).

```bash
cd /Users/chabanovz/work/hello_tizen_tv
echo "Decision: env-var path exhausted. Escalating to Approach B." >> docs/FINDINGS.md
# Plus paste actual log evidence
git add docs/FINDINGS.md && git commit -m "docs(emulator): iter8 task5 — env vars not honored, escalate to Approach B"
```

---

## Task 6 (alternate-path branch): Flutter hardcoded EGL — patch libflutter_tizen.so

**Gate:** Task 4 step 6 chose (b) or (c).

**Files:**
- Read host: `~/tizen-studio-data/emulator/vms/hello_tv/logs/emulator.klog` (find Flutter EGL stack trace)
- Modify inside guest TPK: `lib/libflutter_tizen.so` (the embedder shared library)

- [ ] **Step 1: Extract libflutter_tizen.so from installed TPK on guest, or from build/**

Run:
```bash
ssh popos 'ls ~/development/hello_tizen_tv/build/tizen/tpk/com.example.hello_tizen_tv-1.0.0.tpk
cd /tmp && rm -rf tpk-extracted && mkdir tpk-extracted && cd tpk-extracted
unzip -q ~/development/hello_tizen_tv/build/tizen/tpk/com.example.hello_tizen_tv-1.0.0.tpk
find . -name "libflutter_tizen*"'
```
Expected: `./bin/libflutter_tizen.so` or `./lib/...`.

- [ ] **Step 2: Find ecore_wl2 + EGL call sites in libflutter_tizen.so**

Run:
```bash
ssh popos 'nm -D /tmp/tpk-extracted/<path>/libflutter_tizen.so | grep -iE "ecore_wl2|egl" | head -20
strings /tmp/tpk-extracted/<path>/libflutter_tizen.so | grep -iE "eglGetDisplay|eglCreateWindowSurface" | head -10'
```
(Substitute actual path from step 1.)
Expected: list of EGL symbols.

- [ ] **Step 3: Disassemble surface creation, identify branch**

Run:
```bash
ssh popos 'r2 -q -c "aaa; s sym.imp.eglGetDisplay; axt" /tmp/tpk-extracted/<path>/libflutter_tizen.so 2>&1 | head -20'
```
Expected: callers listed. Find the caller that handles return value — if eglGetDisplay returns failure, fallback or abort.

- [ ] **Step 4: Pause — this gets specific to disasm shape, document approach in FINDINGS**

Document the failed EGL call chain shape, propose specific patch (e.g., NOP the error check so engine continues with sw raster path). Then either:

(a) Apply patch, repackage TPK, re-install, retest.
(b) Conclude Approach A insufficient, escalate to Approach B.

This sub-task is itself a mini binary-RE block — if you find a clean patch in <2h, proceed; otherwise escalate.

---

## Task 7: Document success, capture reproduction recipe, commit artifacts

**Gate:** Task 4 step 6 chose (a) — counter UI visible.

**Files:**
- Write: `docs/start-tizen-emulator.sh` (update with new launch sequence)
- Write: `docs/static-fb-test/iter8-success-screenshot.png`
- Append: `docs/FINDINGS.md` Iteration 8 final result

- [ ] **Step 1: Save success screenshot to repo**

Run:
```bash
cp /tmp/shots-popos/iter8-task4.png /Users/chabanovz/work/hello_tizen_tv/docs/static-fb-test/iter8-success-screenshot.png
```

- [ ] **Step 2: Update start-tizen-emulator.sh with iter8 recipe**

The exact diff depends on baseline; outline:
- Apply qcow2 env-var patches (Task 2 commands)
- Launch via `/tmp/run_tv_no_tuner.sh`
- After boot, `flutter-tizen run -d emulator-26101 --enable-software-rendering`

Write the resulting sequence as numbered shell steps. Save to `docs/start-tizen-emulator.sh`.

- [ ] **Step 3: Append final result to FINDINGS**

Append to `docs/FINDINGS.md`:
```markdown

### Task 7 — Iteration 8 result: SUCCESS

Working configuration:
- Emulator binary patched at 0x48bdef (`qt5IsOnscreen=1`) — see iter7
- qcow2 patched: /etc/profile.d/zz-evas-shm.sh + /etc/systemd/system.conf.d/evas-shm.conf with EFL software env vars
- vm_launch.conf: vigs backend=gl, maru-virtual-tuner + maru-external-input-pci commented out
- Samsung-issued cert profile `vld` active (from iter6 transfer)
- Launch: `/tmp/run_tv_no_tuner.sh`, then `flutter-tizen run -d emulator-26101 --enable-software-rendering`

Screenshot: docs/static-fb-test/iter8-success-screenshot.png — Flutter counter UI visible inside Tizen TV emulator skin canvas at ~<measured> fps.
```

- [ ] **Step 4: Commit all artifacts**

Run:
```bash
cd /Users/chabanovz/work/hello_tizen_tv
git add docs/FINDINGS.md docs/static-fb-test/iter8-success-screenshot.png docs/start-tizen-emulator.sh
git commit -m "feat(emulator): iter8 WIN — Flutter UI rendering via EFL shm backend"
scp docs/FINDINGS.md docs/start-tizen-emulator.sh popos:/home/vld/development/hello_tizen_tv/docs/
```

- [ ] **Step 5: Update memory file for future sessions**

Append to `/Users/chabanovz/.claude/projects/-Users-chabanovz-work-hello-tizen-tv/memory/project_tizen_emulator.md`:

```markdown
**ITERATION 8 SUCCESS (2026-05-22 Linux Pop!_OS):** Flutter UI renders in emulator via EFL software backend. Key recipe: emulator binary qt5IsOnscreen=1 patch + qcow2 env-var injection (EVAS_RENDER_ENGINE=wayland_shm + ELM_ENGINE=wayland_shm + ELM_ACCEL=none) + vigs backend=gl + no tuner devices + Samsung-issued cert + `--enable-software-rendering`. See docs/superpowers/specs/2026-05-22-tizen-emulator-ui-linux-design.md and docs/superpowers/plans/2026-05-22-approach-a-efl-shm-backend.md and Iteration 8 in docs/FINDINGS.md.
```

---

## Self-Review

Spec coverage check:
- A1 (mount qcow2, inventory shm) → Task 1 ✓
- A2 (inject env vars) → Task 2 ✓
- A3 (boot + observe) → Task 3 ✓
- A4 (flutter-tizen run + screenshot) → Task 4 ✓
- A5 (fallback within A: env var detection) → Task 5 ✓
- A6 (binary patch libflutter_tizen) → Task 6 ✓
- A7 (document success) → Task 7 ✓
- Stop conditions: explicit gate at Task 3 step 7, Task 4 step 6, Task 5 step 5 ✓
- FINDINGS continuation: every task appends a "Task N result" block ✓

Placeholder check: One angle-bracket placeholder in Task 6 (`<path>` — actual TPK extraction path determined at runtime). All other placeholders are template fields engineers fill with observed values (counts, screenshot results, decisions). These are acceptable because they're outputs to capture, not skipped work.

Type/signature consistency: env-var names consistent across Tasks 2/5 (added EVAS_ENGINE in Task 5 if needed). File paths consistent. Backup naming (`enlightenment-guest`, `emulator-x86_64.orig`) consistent.

Scope: focused entirely on Approach A. Approach B and C tracked in spec but not in this plan (they will get their own plan files if triggered).
