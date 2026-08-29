# Pocket Option Telegram Bot — Salam port

The same conditional-order bot as the TypeScript version in the parent
directory, rewritten in [Salam](https://github.com/SalamLang/Salam). It is a
single native binary with no runtime: `salam build main.salam` produces
`bot`, which links SQLite and speaks socket.io and the Telegram Bot API
through the standard library.

```sh
SALAM=~/Projects/SalamLang/Salam/salam ./build.sh   # builds ./build/bot and the checks
./build/tests                                       # 125 assertions, no network
./build/bot                                         # reads the same .env as the TS version
```

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

## The modules

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

## Checks

`build.sh` also builds four programs used to verify the port against the real
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

## Differences from the TypeScript version

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

## Environment

The same `.env` as the TypeScript version, minus `DISPLAY_TIMEZONE` (see
above). `TELEGRAM_BOT_TOKEN` is the only required value; everything else has
the documented default.
