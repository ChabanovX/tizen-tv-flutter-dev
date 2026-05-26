# Samsung TV Flutter deploy via Remote Test Lab — end-to-end guide

Workflow для разработки Flutter Tizen TV без покупки реального
Samsung TV: используем Samsung Remote Test Lab (RTL), который даёт
доступ к реальным Samsung Smart TV в дата-центре Samsung через
sdb-туннель и web stream живого экрана.

Этот guide собран из реальных проб 2026-05-26 на Mac (Tailscale →
popos для Flutter Tizen builds). Документирует точно то что нужно
сделать и где можно споткнуться.

## Что RTL **на самом деле**

**RTL = реальные физические TV в дата-центре Samsung в Корее.**
- Не эмулятор. Реальное железо.
- Бесплатно для зарегистрированных в Samsung Seller Office
- Сессии ~30 мин, можно перерезервировать
- Видишь TV через **live video stream в браузере** (WS-based, без Java/JNLP в современной версии)
- Управляешь TV remote control buttons прямо в браузере
- Можешь `sdb install <tpk>` твоё приложение
- Видишь рендер UI в том же live stream

**Pool моделей:**
- NEO QLED 4K QN55QN80F (2025) — Tizen 8/9
- QLED 4K QN55Q80D (2024) — Tizen 7.5/8
- QLED 4K QC80 (2023) — Tizen 7
- ... и старше до 2019
- Lifestyle The Sero (2022)

20+ available units на каждую модель обычно.

## Pre-requisites (один раз)

### Хост: macOS

```bash
# 1. Tizen Studio CLI (минимальный)
brew install --cask tizen-studio   # или скачать https://developer.tizen.org/development/tizen-studio/download
# Проверь:
~/tizen-studio/tools/sdb version   # → Smart Development Bridge version 4.x.x

# 2. flutter-tizen (если ещё нет на маке — на popos уже есть)
git clone https://github.com/flutter-tizen/flutter-tizen.git ~/development/flutter-tizen
export PATH="$HOME/development/flutter-tizen/bin:$PATH"

# 3. Samsung sdbproxy для RTL (one-time):
#    Download RTL TV Tools macOS extension:
curl -L -o /tmp/RTL_TV_TOOLS_macos.zip \
  "https://developer.samsung.com/smarttv/file/243dee80-63e3-43c6-9c31-dc0717cd94bc"
unzip /tmp/RTL_TV_TOOLS_macos.zip -d /tmp/rtl-tools
cd /tmp/rtl-tools && unzip binary/tv-samsung-sdbproxy_*_macos-64.zip -d sdbproxy
mkdir -p sdbproxy/data/tools
cp ~/tizen-studio/tools/sdb sdbproxy/data/tools/sdb
cd sdbproxy && INSTALLED_PATH=$PWD/data bash install.sh

# This creates ~/.sdbproxy/ with the proxy daemon, AppleScript URL handler,
# and registers sdbproxy:// URL scheme in macOS LaunchServices.
```

Verify:
```bash
ls ~/.sdbproxy/
# Should contain: sdbproxy, sdb, APP-sdbproxy.app, URL-sdbproxy.app, script.sh

open "sdbproxy://test"
# Should open Terminal window briefly running sdbproxy
```

### Samsung Seller Office account

1. https://seller.samsungapps.com/tv/ → Sign Up
2. Email + ID + Russian/foreign ИНН/идентификатор (work as personal seller)
3. Wait approval (1-2 days). Free.

### Samsung Author Certificate (one-time)

Через Tizen Studio Mac app: **Tools → Certificate Manager → Create New Certificate**:
- Type: **Samsung**
- Profile name: пусть будет `vld` (или твоё имя)
- Save to `~/SamsungCertificate/<project>/`
- Issue Author Certificate → Samsung backend подпишет

### Samsung Distributor Certificate (one-time, **критический для RTL**)

Это **узкое место workflow**. Distributor cert привязан к DUIDs (Device Unique IDs) конкретных TV. Без DUID этой TV в cert → `Operation not allowed` при install.

Для **RTL TV** Samsung имеет пул DUID'ов. Регистрация:

1. Открыть RTL session на любую модель TV (Steps 1-3 ниже)
2. Получить DUID из sdb: `sdb shell 0 vital_info | grep DUID`
3. В **Tizen Studio Certificate Manager → твой Profile → Distributor Certificate → Manage → Add Device ID**
4. Внести DUID. Можно несколько за раз (по DUID на каждую модель)
5. Reissue + auto-replace distributor.p12 в `~/SamsungCertificate/<project>/`

> **Альтернатива:** Samsung Partner cert tier (платный, требует приглашения) даёт wildcard DUID — install на любой Samsung TV без перерегистрации.

## Сессия RTL — каждый раз

### 1. Бронирование TV

1. https://developer.samsung.com/remotetestlab/devices/117/tv
2. Найти доступную модель (`Available (N)` где N>0)
3. Клик на карточку → **Start** в всплывающем меню
4. Открывается новая вкладка `developer.samsung.com/remotetestlab/tvclient/target` с live video stream + sidebar

### 2. SDB connect

В RTL client (левый sidebar):
1. Клик **SDB** icon
2. Появляется dialog "Configuration is required for sdb" → клик **Confirm**
3. Браузер показывает popup **"Open URL-sdbproxy.app?"** → **Open** + чекни **«Always allow»** (один раз)
4. Открывается Terminal window:
   ```
   ~/.sdbproxy/sdbproxy create_sdb_proxy "sdbproxy://connect?sid=<TOKEN>&url=wss://www.s-tomato.co.kr/tv/<N>/ctd/"
   Do you want to set https proxy server? (y/n or Enter to skip) :
   ```
5. Нажми **Enter** (skip proxy)
6. Через 5-10 сек:
   ```
   connecting to 127.0.0.1:<PORT> ...
   connected to 127.0.0.1:<PORT>
   List of devices attached 
   127.0.0.1:<PORT>     device    QN55QN80FAFXZA
   ```

### 3. Build + install + launch

```bash
cd ~/your_flutter_tizen_project   # на popos или на маке если flutter-tizen стоит
flutter-tizen build tpk --release --device-profile tv --target-arch arm --security-profile vld
# → build/tizen/tpk/your_app.tpk

# Если строил на popos — pull на мак:
scp popos:.../your_app.tpk /tmp/

# Install на real TV через RTL tunnel:
~/tizen-studio/tools/sdb -s 127.0.0.1:<PORT> install /tmp/your_app.tpk

# Launch:
~/tizen-studio/tools/sdb -s 127.0.0.1:<PORT> shell app_launcher --start <appid>
```

Если install падает `[118, -4] Operation not allowed`:
- Distributor cert не содержит DUID этой RTL TV
- Получи DUID через `sdb -s 127.0.0.1:<PORT> shell 0 vital_info`
- Добавь в cert (Pre-requisites шаг "Distributor Certificate")
- Re-build + re-install

### 4. Видишь пиксели

UI твоего Flutter app рендерится на реальной TV. Live video stream в браузере (вкладка `tvclient/target`) показывает реальные пиксели реального Samsung TV. Latency 200-500ms.

Visual UI iteration выполняется через RTL stream. Не идеально для pixel-perfect QA, но отлично для:
- Visual verification что UI выглядит правильно
- Navigation flow check (remote control buttons работают)
- Crash на старте? Видишь сразу.
- Layout breaks на TV resolution

### 5. Завершение сессии

Сессия истекает по timeout (~30 мин). Можно перебронировать сразу.
TV ребутается между сессиями — твой install не сохраняется.

## Что НЕ работает / known limits

| Проблема | Workaround |
|---|---|
| Hot reload Flutter | ❌ нет direct dart VM service port forward через RTL. Используй `--release` mode, перезаливай при каждой итерации |
| `flutter-tizen run` cleanly | ❌ `run` ожидает прямое sdb. Используй разбивку `build` → `sdb install` → `sdb shell app_launcher --start` |
| Видеть Flutter dlog через sdb dlog | ⚠️ Samsung TV's sdb может ограничивать. Используй `sdb shell dlogutil` |
| Latency live stream | ~300ms — нормально для UI debug, плохо для скорости animations |
| Долгие сессии | Самый длинный slot — 2 часа (на старых моделях больше credits) |
| Cross-model testing | Нужно по DUID per model в cert. Регистрируй DUID'ы сразу всех моделей которые планируешь тестить |

## Когда RTL **не подходит** и нужен real TV в офисе

- Continuous integration / автоматизированные UI тесты → нужен dedicated TV
- Большой объём итераций / много часов в день
- Performance / FPS measurements (RTL latency искажает)
- Visual quality / pixel-perfect QA (stream compression)
- Network testing (TV в Samsung infra, не в твоей сети)

Покупка Samsung TV: ~$300-500 за consumer model (RU/QN series 2021+ = Tizen 6+).

## Cheat sheet — самое короткое из всего

```bash
# Одноразовый setup macOS:
mkdir -p ~/.sdbproxy && curl -L .../RTL_TV_TOOLS_macos.zip | bsdtar -xvf - -C ~/.sdbproxy --strip-components=1
INSTALLED_PATH=~/.sdbproxy/data bash ~/.sdbproxy/install.sh

# Каждая сессия:
# 1. Browser: бронируй TV в developer.samsung.com/remotetestlab/devices/117/tv → Start
# 2. RTL client → SDB icon → Confirm → Open in Chrome popup → Enter в Terminal
# 3. Terminal:
~/tizen-studio/tools/sdb -s 127.0.0.1:$PORT install your.tpk
~/tizen-studio/tools/sdb -s 127.0.0.1:$PORT shell app_launcher --start your.appid
# 4. Watch pixels in browser RTL stream
```

## Архитектурная карта

```
[Your Mac]                                  [Samsung Datacenter, Korea]
  |
  ~/.sdbproxy/sdbproxy ────WSS tunnel────► s-tomato.co.kr (RTL backend)
  |        ▲                                       │
  |        │ stdin: Enter (skip proxy)              │
  |        │                                       ▼
  ~/tizen-studio/tools/sdb                  Real Samsung TV
  |  └─ connect 127.0.0.1:<port>  ──tunneled SDB── (QN55QN80F etc)
  |     └─ install .tpk           ───────►        │
  |     └─ shell app_launcher                     ▼
  |                                          [Flutter app runs]
  |        Chrome live video stream ◄─────       │
  |        (developer.samsung.com/                ▼
  |         remotetestlab/tvclient/target)  [pixels visible]
```

## Provenance

Этот guide собран после ~3-часовой пробы 2026-05-26 на:
- Mac M-series (Apple Silicon, macOS 25.0.0)
- popos на Tailscale для Flutter Tizen builds
- Chrome 148 в debug режиме для CDP exploration
- Samsung Seller Office personal partner account
- Samsung RTL `QN55QN80F` (NEO QLED 4K 2025) test session

Доказали end-to-end pipeline до `sdb install`. Сделали install не получилось
**только потому что Distributor Certificate не содержал DUID конкретно этой
RTL TV** — это штатная Samsung partner workflow которая решается one-time
регистрацией DUID в Certificate Manager.
