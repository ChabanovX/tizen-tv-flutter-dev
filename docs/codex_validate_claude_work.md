Ниже версия отчёта для других разработчиков, без ссылок на локальные файлы.

**Отчёт: Flutter Tizen на Mac Apple Silicon**

Цель исследования: понять, можно ли на macOS Apple Silicon разрабатывать Flutter-приложение для Samsung TV Tizen и запустить TV Tizen emulator, несмотря на то что официальный Samsung/Tizen emulator рассчитан на x86/x86_64.

**Что удалось**

Flutter-Tizen toolchain сам по себе работает. Проект `hello_tizen_tv` успешно собирается в `.tpk`.

Локальный Tizen SDK из VSCode Tizen Extension оказался частично неполным: были установлены TV emulator packages, но отсутствовали common emulator helpers:

```bash
qemu-img
check-hax
check-cam
```

После восстановления недостающих файлов из официальных пакетов Tizen emulator profile creation стала возможна.

Главный прорыв: рабочий запуск получился не через bundled Samsung `emulator-x86_64`, а через обычный `qemu-system-x86_64` на Apple Silicon в режиме TCG.

Текущий результат проверен:

```bash
sdb devices
# emulator-26101    device    Tizen_TV_HD1080

flutter-tizen devices
# Tizen Tizen_TV_HD1080 (tv) • emulator-26101 • tizen-x64 • Tizen 10.0 (emulator)
```

Также `sdb capability` подтверждает:

```text
profile_name: tv
vendor_name: Samsung
platform_version: 10.0
cpu_arch: x86_64
can_launch: tv-samsung
filesync_support: pushpull
```

То есть VM действительно поднялась, SDB работает, Flutter-Tizen видит её как Tizen TV emulator.

**Ключевая находка**

Проблема была не только в QEMU, HAX или графике. Важный недостающий параметр был в kernel cmdline:

```text
host_ip=10.0.2.2
```

Без него guest-side `sdbd` внутри Tizen не регистрировался у host SDB server.

Выяснилось, что `sdbd` внутри guest подключается наружу к host:

```text
10.0.2.2:26099
```

То есть он использует SLIRP networking и outbound connection к host SDB server. Поэтому перед boot VM нужно запускать:

```bash
sdb start-server
```

Минимально важные kernel cmdline параметры:

```text
vm_name=Tizen_TV_HD1080
host_ip=10.0.2.2
sdb_port=26100
ip=10.0.2.15::10.0.2.2:255.255.255.0::eth0:off
```

**Как сейчас стартует emulator**

Сейчас используется скрипт вида:

```bash
qemu-system-x86_64 \
  -accel tcg \
  -machine pc \
  -cpu Haswell-noTSX \
  -smp 4 \
  -m 1024 \
  -drive file=tizen_overlay.qcow2,if=virtio,format=qcow2,cache=writeback \
  -kernel bzImage.x86_64 \
  -append "vm_name=Tizen_TV_HD1080 video=LVDS-1:1920x1080-32@60 dpi=72 clocksource=hpet consoleblank=0 console=ttyS0 model=4ksero ip=10.0.2.15::10.0.2.2:255.255.255.0::eth0:off host_ip=10.0.2.2 sdb_port=26100, vm_resolution=1920x1080" \
  -netdev user,id=net0,hostfwd=tcp::26101-:26101,hostfwd=tcp::26102-:26102 \
  -device e1000,netdev=net0 \
  -display none \
  -no-reboot \
  -nodefaults
```

На конкретной машине есть готовый helper:

```bash
bash /tmp/tizen-utm/start-tizen-emulator.sh
```

После запуска:

```bash
sdb devices
flutter-tizen devices
```

**Что не удалось / ограничения**

Это не полноценный официальный Samsung emulator flow через VSCode UI. Это обходной запуск Samsung Tizen TV image через stock QEMU.

Bundled Samsung emulator на Apple Silicon остаётся проблемным. Он x86_64, работает через Rosetta, требует старые assumptions вокруг HAX/TAP/MARU/VIGS и нестабилен в этой среде.

Графический стек пока не считается рабочим. VM запущена headless через:

```text
-display none
```

В guest logs видны ошибки display/DRM/AVE/AVOC:

```text
drm_fd open failed
avocd_edid_init_routine ... event failed
```

То есть SDB и boot работают, но интерактивный TV UI пока не подтверждён.

Flutter package deploy ещё не подтверждён до конца. Существующий `.tpk` успешно передался через SDB, но установка упала на сертификате:

```text
install failed[118, -12], reason: Check certificate error
```

Следующий практический blocker: создать корректный Samsung/Tizen TV signing profile, пересобрать `.tpk`, затем повторить:

```bash
flutter-tizen run -d emulator-26101
```

**Текущий статус**

Работает:

```text
Tizen TV 10.0 guest boots
SDB connection works
flutter-tizen sees emulator-26101
file push over SDB works
```

Не доказано:

```text
correct app installation
Flutter app launch
interactive TV graphics/output
remote-control/UI testing
```

Главный вывод: на Apple Silicon возможно поднять Tizen TV image до состояния SDB-ready через stock QEMU/TCG, но это пока developer workaround, а не полноценная замена официальному Samsung TV emulator.