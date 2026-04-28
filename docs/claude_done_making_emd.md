## 🎉 Tizen TV emulator working on Apple Silicon Mac!

**Reverse-engineering succeeded.** The blocker wasn't evdi after all — it was a missing kernel cmdline parameter `host_ip=`. The full chain we uncovered:

1. **Extracted `emuld`, `libemuld.so`, and `sdbd` ELF binaries** from the Tizen image (offsets `0x4563c000`, `0x2d796000`, `0x2d2e9000` in the raw image)
2. **Found the `sdbd-env-generator`** systemd generator that builds `SDBD_CMDLINE` from `/proc/cmdline`'s `sdb_port=` and `vm_name=`, including `--connect-to=10.0.2.2:26099`
3. **Discovered sdbd connects OUTBOUND** to `host_ip:26099` (not inbound on 26101 like systemd socket activation suggested), which routes through SLIRP to the host's SDB server
4. **Found the missing parameter**: sdbd reads `host_ip=` from `/proc/cmdline`, logs `failed to get emulator host ip` and refuses to register without it. Samsung's emulator binary inserts this; stock QEMU doesn't.
5. **emuld's `open /dev/evdi0 fail` is harmless** — emuld continues running, parses `ip=` from cmdline itself, and sets Smack netlabels

### Required cmdline params (added to stock QEMU boot):
```
host_ip=10.0.2.2
sdb_port=26100
vm_name=Tizen_TV_HD1080
ip=10.0.2.15::10.0.2.2:255.255.255.0::eth0:off
```

### Verified results:
- `sdb devices` → `emulator-26101 device Tizen_TV_HD1080` ✅
- `sdb capability` returns full TV info (profile=tv, vendor=Samsung, platform=10.0) ✅  
- `sdb push` transfers files ✅
- Boot ~100s vs 5-10min on Samsung's bundled QEMU 2.8 ✅
- **Zero GPF crashes** vs 21+ on Samsung's QEMU ✅

### Reusable: `/tmp/tizen-utm/start-tizen-emulator.sh`
A turnkey script that spins up the emulator and waits for SDB ready. Run it whenever you need the emulator.

You can now run `flutter-tizen run` against `emulator-26101`. The emulator currently running has SDB ready — try it now if you'd like to verify a Flutter deploy.