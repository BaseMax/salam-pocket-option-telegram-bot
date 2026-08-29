# Pocket Option Telegram Bot

A Telegram-controlled **conditional order** bot for [Pocket Option](https://pocketoption.com)
binary options, written in [Salam](https://github.com/SalamLang/Salam).

You tell it a price. It keeps that instrument's live tick stream open, and the moment the market
touches your price it opens the trade for you and reports back: entry, win, loss, and the account
balance on every update.

Because these are binary options, there is **no stop loss and no take profit** anywhere in the
system. The only exit is the expiry the trade was opened with.

The bot is a single native binary with no runtime - no Node, no Bun, no interpreter. It links
SQLite and speaks socket.io and the Telegram Bot API through the standard library.

---

## What it does

**Per order you specify:**

| Field | Meaning |
| --- | --- |
| Symbol | e.g. `GBPAUD_otc`, `EURUSD` |
| Direction | buy (`call`) or sell (`put`) |
| Trigger price | the price the market has to reach |
| Entry mode | `touch`: enter on the very tick that hits the price<br>`next_candle`: the touch only arms the order; enter on the first tick of the next candle |
| Expiry mode | `fixed`: stay in for exactly N seconds<br>`floating`: ride to the close of the current candle (or the N-th candle) |
| Chart | timeframe (5s … 4h) and type (candle / heikin-ashi / line) |
| Amount | trade size in USD |
| Account | demo or real, these are physically different broker clusters |
| Validity | optional deadline after which an untriggered order is abandoned |

**Triggering is a crossing, not proximity.** When the order is created the bot samples the market and
records which side of the trigger it sat on. An order placed above the market only fires when the
price rises into it; one placed below only fires when the price falls into it. A tick that gaps
straight over the trigger still counts.

**One live session per watched instrument.** Each `(account, symbol)` pair that has an active order
gets its own authenticated socket to the broker, kept alive with the broker's own ping cadence and
re-subscribed automatically across reconnects. Sessions are reference-counted by the orders that need
them and torn down shortly after the last one settles.

**Everything survives a restart.** Orders live in SQLite and every state transition is written
through. On boot the engine re-attaches each pending, armed and open order. The one exception is an
order that was mid-flight when the process died: rather than risk a duplicate trade, it is flagged
for you to check on the broker.

---

## Quick start

```bash
./build.sh                # or SALAM=/path/to/salam ./build.sh
cp .env.example .env      # then fill in the two required values
./build/bot
```

Minimum `.env`:

```bash
TELEGRAM_BOT_TOKEN=123456:AA...
TELEGRAM_ADMIN_IDS=              # leave empty; the first /start claims the bot
```

Then in Telegram: `/start`, and give the bot a broker session with `/session demo <SSID>`.

### راه‌اندازی سریع (فارسی)

۱. با `./build.sh` ربات را بسازید؛ فایل اجرایی در `build/bot` ساخته می‌شود.
۲. فایل `.env.example` را به `.env` کپی کنید و `TELEGRAM_BOT_TOKEN` را بگذارید.
۳. `./build/bot` را اجرا کنید.
۴. در تلگرام `/start` بزنید؛ اولین چت مالک ربات می‌شود.
۵. با `/session demo <SSID>` نشست پاکت آپشن را ثبت کنید (راهنمای گرفتن SSID را با دستور `/session` ببینید).
۶. با `/new` سفارش بسازید یا از دستور تک‌خطی `/order` استفاده کنید.

---

## Getting your Pocket Option SSID

The bot authenticates over **socket.io** exactly as the web app does (it uses the `socket.io-client`
library against `wss://demo-api-eu.po.market/socket.io/?EIO=4&transport=websocket`), so it needs the
auth frame your browser sends.

1. Log into the account you want in a browser and open its trading screen:
   - demo: `https://p.finance/fa/cabinet/demo-quick-high-low/`
   - real: `https://p.finance/fa/cabinet/quick-high-low/`
2. Open DevTools (F12) → **Network** → filter **WS** → reload the page.
3. Click the connection whose URL looks like
   `demo-api-eu.po.market/socket.io/?EIO=4&transport=websocket`
   (for a real account: `api-eu.po.market`).
4. Open the **Messages** tab. After the server's `40{"sid":"…"}` handshake you will see an outgoing
   frame starting with `42["auth",`.
5. Send that whole frame to the bot:

```
/session demo 42["auth",{"sessionToken":"…","uid":"…","lang":"fa","currentUrl":"cabinet/demo-quick-high-low","isChart":1}]
```

Both auth dialects are supported, and the bot recognises either success reply:

| Front-end | Auth frame key | Success reply |
| --- | --- | --- |
| p.finance (current) | `sessionToken` | `42["auth/success"]` |
| older / pocketoption.com | `session` | `successauth` |

The bot deletes the message carrying the SSID immediately, then tests the connection so you get a
straight yes/no rather than a silent failure.

> ⏳ **Sessions are short-lived.** Capture the frame from a tab that is logged in *right now*; a
> token copied days earlier is almost always dead. The two failure modes are distinguished for you:
> a `session` frame the broker rejects is dropped within milliseconds with `NotAuthorized`, while a
> stale `sessionToken` frame is silently ignored and is reported after the auth timeout. In both
> cases the bot stops reconnecting, tells you, and leaves your pending orders intact until you send
> a fresh SSID.

The SSID can also be pre-loaded from `.env` (`PO_DEMO_SSID` / `PO_REAL_SSID`); values set from
Telegram take precedence and persist in the database.

---

## Commands

| Command | Purpose |
| --- | --- |
| `/new` | Interactive order builder, every field on one inline keyboard |
| `/order …` | One-line order (see below) |
| `/list` | Active orders, with live price and a cancel button |
| `/cancel <id>` | Cancel a pending or armed order (an open trade cannot be cancelled) |
| `/history` | Recent orders |
| `/stats` | Wins / losses / net P&L over the last 24h |
| `/balance [demo\|real]` | Account balance |
| `/price <symbol>` | Live price |
| `/symbols [query]` | Broker symbol list, or a search through it |
| `/status` | Session health, endpoints, broker clock offset |
| `/mode demo\|real` | Default account |
| `/settings`, `/set <key> <value>` | Defaults for new orders |
| `/session demo\|real <SSID>` | Store and test broker credentials |
| `/start`, `/help` | The guide, with pages on charts, time formats and entry rules |
| `/id` | Your chat id |

### One-line order syntax

```
/order <symbol> <buy|sell> <price> [key=value …]
```

```
/order GBPAUD_otc buy 1.95320 tf=1m dur=60 amount=1 acc=demo
/order EURUSD sell 1.08540 tf=1m exp=float candles=1 entry=next
```

| Key | Values | Default |
| --- | --- | --- |
| `tf` | `5s`, `1m`, `5m`, `1h`, … | `/set tf` |
| `chart` | `candle`, `ha`, `line` | `/set chart` |
| `entry` | `touch`, `next` | `/set entry` |
| `exp` | `fixed`, `float` | `/set expiry` |
| `dur` | `60`, `1m`, `31s` (implies `exp=fixed`) | `/set dur` |
| `candles` | `1`, `2`, … (implies `exp=float`) | `/set candles` |
| `amount` | USD | `/set amount` |
| `acc` | `demo`, `real` | `/mode` |
| `valid` | `30m`, abandon if never triggered | none |

Every value is read leniently. Durations accept any unit spelling in either language and any
case: `90`, `1m`, `1M`, `2 minutes`, `۳۰ دقیقه`, `1h 30m`, `2 ساعت و ۱۵ دقیقه`, `3 days`, `1 ماه`
(a bare number means seconds). Direction, account, chart and entry words accept their Persian
equivalents too (`خرید` / `فروش`, `واقعی`, `هایکن`, `بعدی`), and Persian digits work everywhere.

---

## How expiry is computed

`fixed` maps to the broker's relative `time` field: *N seconds from the fill*.

`floating` needs the trade to land exactly on a candle close, so it uses the broker's absolute
`closeAt` field. That field is expressed in the **broker's** timezone, so the client starts from
`PO_SERVER_TIME_OFFSET` (default `7200`) and re-learns the true offset from the first order
acknowledgement, which keeps it correct across DST changes. If the broker still rejects the absolute
expiry, the engine retries the same trade with the equivalent relative duration.

If a floating order would expire within `MIN_DURATION_SECONDS` of the fill, it rolls forward to the
next candle instead of opening a trade that is over before it starts.

---

## Architecture

| file | what it owns |
| --- | --- |
| `main.salam` | startup and the loop |
| `config.salam` | the environment, and the order limits |
| `types.salam` | Order, OrderSpec, and the vocabulary constants |
| `store.salam` | SQLite: schema, orders, settings |
| `settings.salam` | the defaults `/set` changes, and stored credentials |
| `timex.salam` | duration parsing and formatting, candle boundaries, prices |
| `jsonx.salam` | the JSON arrays the broker sends, read defensively |
| `ssid.salam` | both dialects of the pasted auth frame |
| `broker.salam` | the Pocket Option socket: auth, ticks, assets, orders, deals |
| `symbols.salam` | symbol spelling, matching and search |
| `engine.salam` | the order state machine |
| `parse.salam` | the one-line `/order` command and every choice word |
| `texts.salam` | all Persian copy, including the guides |
| `tgapi.salam` | Telegram calls and inline keyboards |
| `wizard.salam` | the `/new` panel |
| `tgbot.salam` | commands, callbacks, notifications |

## Why it is shaped this way

**One thread, one loop.** `main.salam` pumps the broker sockets, moves the
orders that can move, drains the engine's event queue into Telegram messages,
and asks Telegram for new commands - about ten times a second. The TypeScript
version leaned on an event loop and callbacks; Salam lambdas capture by value
and cannot write back to their surroundings, so every layer here *returns*
what happened and the loop passes it on. That turned out to suit the domain:
the engine is a state machine over rows, not a web of listeners.

**Queues instead of callbacks.** `engine.TakeEvent()` and `broker.TakeDeal()`
hand the caller one thing at a time. Nothing in the trading rules knows that
Telegram exists, and `tgbot.salam` never reaches into the engine's state.

**SQLite is the truth.** Every state transition is written before it is
announced, so a restart re-attaches pending, armed and open orders from the
database. An order that was mid-flight when the process died is flagged
`failed` rather than retried, exactly as in the TypeScript version - the one
thing worse than a missed trade is a duplicated one.

Order lifecycle:

```
pending ──price touches trigger──┬─ touch mode ──────────────► placing ─► open ─► won / lost / draw
                                 └─ next_candle ─► armed ─► (candle opens) ─► placing ─► open ─► …
```

`pending` also ends in `cancelled` (by you) or `expired` (validity elapsed); any step can end in
`failed` if the broker refuses the trade.

---

## Running with Docker

The image is built in two stages: the first compiles the sources with the
Salam compiler and **runs the test suite**, so an image that builds is an
image whose bot passed its tests; the second keeps only the binary, SQLite
and a CA bundle. It runs as a non-root user with a read only root filesystem,
and only `./data` is writable, which is where the database lives.

```bash
cp .env.example .env                            # then fill in the token and the SSID
mkdir -p data && sudo chown -R 1000:1000 data   # 1000:1000 is the image's own bot user
SALAM=/path/to/salam ./build.sh image           # builds pocket-option-telegram-bot:latest
docker compose up -d
docker compose logs -f
```

`./build.sh image` stages the compiler and its standard library into
`.salam-toolchain/` (gitignored, removed again afterwards) because the
socket.io client this bot needs is newer than the last published Salam
release. Once a release carries `std/net/socketio`, the Dockerfile can fetch
its own compiler with the official `install.sh` and this step disappears -
the comment at the top of the Dockerfile says where.

**Deploying to a machine without a Salam compiler.** Build the image where the
compiler is, and ship the image rather than the source:

```bash
SALAM=/path/to/salam ./build.sh image
docker save pocket-option-telegram-bot:latest | gzip | ssh user@server 'gunzip | docker load'
ssh user@server 'cd /path/to/app && docker compose up -d'
```

To keep the database owned by your own user instead of 1000:1000, point the
container at it:

```bash
sed -i "s/^DOCKER_UID=.*/DOCKER_UID=$(id -u)/; s/^DOCKER_GID=.*/DOCKER_GID=$(id -g)/" .env
sudo chown -R "$(id -u):$(id -g)" data
docker compose up -d --force-recreate
```

The database is a bind mount, not a Docker volume: `./data` on the host is
mounted at `/app/data` in the container, so `data/bot.sqlite` stays in the
project directory where you can read, copy and back it up normally. Point
`DATA_DIR` in `.env` somewhere else if you want it in another path.

`DOCKER_UID` / `DOCKER_GID` must match the owner of `./data` on the host,
otherwise the container cannot write the database, and deploying as root is
the usual way to get this wrong: a freshly cloned `./data` is owned by `root`,
while the container runs as uid 1000. The entrypoint checks the directory
before startup and prints the exact `chown` to run instead of failing later on
a write. The mount is declared with `create_host_path: false`, so a missing
`./data` stops compose with a clear message rather than creating a root owned
directory.

The container writes a heartbeat file every 30 seconds and the healthcheck
marks it unhealthy once that file is older than two minutes, so a process that
is technically alive but no longer working shows up in `docker ps` as
unhealthy. With `restart: unless-stopped` the bot comes back after a crash or
a reboot, and pending orders are re-attached from SQLite on startup.

Useful commands:

```bash
docker compose ps                        # health status
docker compose restart bot               # after changing .env
cp data/bot.sqlite backup-$(date +%F).sqlite   # back up orders and settings
```

Stopping is graceful: `docker compose stop` sends SIGTERM, the bot stops
polling, closes the broker sockets and the database, and exits within the 20
second grace period. Open trades keep running at the broker and are reconciled
on the next start.

## Configuration

Everything is optional except `TELEGRAM_BOT_TOKEN`. See `.env.example` for the full list; the
notable ones:

| Variable | Default | Purpose |
| --- | --- | --- |
| `TELEGRAM_ADMIN_IDS` | *(empty)* | Allowed chat ids. Empty means the first `/start` claims the bot |
| `PO_DEMO_SSID` / `PO_REAL_SSID` | *(empty)* | Seed credentials; `/session` overrides and persists |
| `PO_DEMO_SERVERS` / `PO_REAL_SERVERS` | built-in list | `url` or `url|origin`, comma separated |
| `PO_SERVER_TIME_OFFSET` | `7200` | Starting guess for the broker clock offset |
| `MIN_DURATION_SECONDS` | `5` | Broker floor for a binary option |
| `SESSION_IDLE_TTL_SECONDS` | `60` | How long a session lingers after its last order settles |
| `DISPLAY_TIMEZONE_OFFSET_MINUTES` | `210` | Minutes east of UTC for every timestamp shown |
## Development

```bash
./build.sh          # the bot and every check, into ./build
./build/tests       # the test suite, no network needed
```

### The checks

`build.sh` also builds the programs used to verify the port against the real
services. All of them are demo-account only.

| program | what it proves | touches |
| --- | --- | --- |
| `tests` | durations, symbols, the command parser, the trading rules, SQLite, settings, every notification, 64-bit ids, update polling | nothing |
| `recovery` | what a restart does: mid-flight orders fail, live ones are re-attached | nothing |
| `smoke` | connect, authenticate, asset list, balance, live ticks | broker (read only) |
| `tgcheck` | getMe, an HTML message with an inline keyboard, edit, delete | Telegram |
| `dryrun` | a scripted conversation through the real dispatcher, including the whole panel: both menus, every toggle, each typed value, a rejected one, and submit | Telegram + broker |
| `soak` | four minutes of live ticks: memory, CPU, the expiry rule, idle cleanup | broker (read only) |
| `tradetest` | one $1 demo trade from trigger to settlement | broker (places a trade) |

`dryrun` and `tgcheck` never call `getUpdates`, so they can be run while
another instance of the bot is polling the same token.

Measured on the live demo account: 174 assertions pass, four minutes of tick
traffic leave RSS flat at 2 MB and the CPU at 0%, and one $1 trade went
`triggered → opened → settled` with the broker's own deal id.

The one thing no check here covers is `getUpdates` itself: Telegram allows a
single poller per token, so exercising it means being the only bot running on
that token. Everything around it is covered - `Init`, `Apply` (the half of
`Poll` that parses updates and moves the offset, driven by canned Telegram
answers in `tests`), `Dispatch`, `Notify`, and the engine turn.

## Differences from the TypeScript original

This bot began as a TypeScript program; that implementation is in the git
history up to `ac9807e`. Where the two differ:

- **Telegram ids do not fit in 32 bits.** `str.ToInt` is `i32`, which
  silently truncates a modern user id (past 2^31), any supergroup id
  (around -10^12) and every millisecond timestamp. `parse.ParseInt64` reads
  the digits itself, and every id, uid and timestamp goes through it.
- **A refused session is silent.** Pocket Option does not answer a dead token
  with `NotAuthorized`: it accepts the socket, sends the public asset list,
  and then drops the connection - or says nothing at all. `broker.salam`
  reads both as a refusal (a disconnect within three seconds of the auth
  frame having never authenticated, or twelve seconds of silence), so the
  owner is told to send a fresh SSID instead of the bot reconnecting forever.
- **Binary frames.** Pocket Option answers with socket.io binary attachments
  (`{"_placeholder":true,"num":0}` plus the bytes). `broker.Payload()` is the
  one place that matters; without it the socket authenticates and then looks
  silent, which is exactly how this port first behaved.
- **A retired panel keeps its text, not its formatting.** When a tap arrives
  for a panel whose draft is gone (a restart, or an older panel), the bot
  appends the "this panel is over" line to the text Telegram hands back. The
  TypeScript version re-sent the message entities with it; here the summary
  survives as plain text.
- **No candle series.** The TypeScript version aggregated ticks into candles
  and could draw heikin-ashi. The chart type is still carried on every order
  and still explained in the guide, but nothing in the bot renders candles, so
  the aggregation was left out rather than written and never called.
- **Timezone as an offset.** `DISPLAY_TIMEZONE_OFFSET_MINUTES` (default 210,
  Tehran) replaces the IANA name. Iran does not observe daylight saving, so a
  fixed offset is exact; anywhere that does would need `calendar.LoadZone`.
- **Long polling is short polling.** The loop asks Telegram with `timeout=0`
  once a second instead of holding a 30 second long poll, because the same
  thread has to keep the broker sockets pumped.

## Notes and limits

- A refused session is silent: the broker accepts the socket, sends the public asset list and
  then drops the connection rather than answering `NotAuthorized`. The bot reads that as a
  refusal and tells you to send a fresh SSID.
- Pocket Option publishes no API contract. Every frame parser here is defensive, and the client
  treats account-scoped data (a balance push) as proof of authentication so a renamed success event
  cannot strand it. A broker-side change can still break things; `/status` and the connection
  notifications exist to make that obvious quickly.
- The bot never cancels an open binary option, because the broker does not allow it.
- Trade at your own risk. Real-money mode does exactly what you tell it to.
