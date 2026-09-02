# MQTT connection lifecycle on mobile

Notes and rules for how the app's MQTT connection to the Pelion broker behaves
while the app runs, backgrounds, and closes. Written against the current
`MqttTestService` (`lib/features/mqtt/data/mqtt_test.dart`).

## TL;DR

- **Foreground (app visible): a constant connection is achievable and reliable.**
- **24/7 including background / screen-off: NOT possible with a held socket** —
  the OS suspends the app and the broker drops us. This is an OS policy, not a
  bug we can code around.
- **"Running in the background" should be treated as _probably not connected_,
  not as connected.**
- To reach the device while it is backgrounded or closed, use **push
  notifications (FCM / APNs)** — not the MQTT socket.

## Current state (today)

The connection is **not** tied to the app lifecycle. `MqttTestService` is a
singleton that:

- connects **only when the MQTT-test button is tapped** (`connectAndSend()`),
- once connected, is configured to stay up: `autoReconnect = true`,
  `keepAlivePeriod = 10`, and a Last-Will that publishes `offline` if it drops,
- is never started automatically and never reacts to app state changes.

So today it is manual + best-effort. The rules below describe what a proper,
app-managed persistent connection would look like and the limits it must live
within.

## What "down" means — app lifecycle states

The socket's health follows the app's lifecycle state (Flutter exposes these as
`AppLifecycleState`):

| State | Meaning | MQTT connection |
|---|---|---|
| **resumed** | Foreground, visible, fully running | **Connected & healthy** — keepalive pings flow |
| **inactive** | Brief transition (call overlay, app switcher, notification shade) | Still up; no real interruption |
| **paused / hidden** | Backgrounded, process alive but OS throttles/suspends it | **Gray zone** — see below |
| **detached / terminated** | Process gone (user swiped away, or OS killed it) | **Down** — Last-Will fires `offline` |

Key point: it is **not** just "app shut down = disconnected". Backgrounding is
the tricky case.

## The background gray zone (most important section)

Backgrounding is neither an immediate disconnect nor a reliable connection, and
the two platforms differ:

- **Android:** a backgrounded app keeps running for a while, so the socket often
  survives seconds-to-minutes. But Doze / App Standby throttle networking when
  the screen is off, and the OS can suspend or kill the process under memory
  pressure. When it does, keepalive stops.
- **iOS:** much stricter. A backgrounded app is typically **suspended within
  ~30 seconds**, freezing its socket. No background mode short of special
  entitlements keeps a plain MQTT socket alive.

Then the **broker** decides we are gone. With `keepAlive = 10`, if it hears no
ping for roughly **1.5 × keepalive (~15 s)** it declares the client dead, drops
the connection, and publishes our **Last-Will `offline`**.

**Practical rule:** background the app for more than ~15 seconds (guaranteed on
iOS, likely on Android with the screen off) and the server sees us offline, even
though the app may still exist in memory. On returning to the foreground,
`autoReconnect` (plus a resume hook) brings it back and we re-publish `online`.

## keepAlive / Last-Will semantics

- `keepAlivePeriod = 10` → the client sends a ping at least every 10 s.
- The broker tolerates ~1.5 × that (~15 s) of silence before considering the
  client dead.
- On a detected drop (timeout, kill, network loss), the broker publishes the
  retained **Last-Will** message (`status: offline`) to
  `kasa/{licenca}/status/{uredaj}` so the admin sees us go offline automatically.
- On a clean foreground connect we publish a retained `status: online`.

## Recommended design for a persistent (foreground) connection

To get "connected whenever the app is up" done properly:

1. **App-managed, not a button.** Connect automatically on app start (or right
   after login) instead of on a manual tap.
2. **Attach a lifecycle observer** (`WidgetsBindingObserver` /
   `AppLifecycleListener`):
   - on `resumed` → ensure connected + publish `online`,
   - on `paused` / `detached` → let it go (rely on the Last-Will) or explicitly
     publish `offline`, so the admin status is accurate rather than lingering.
3. **Keep `autoReconnect` on** for in-foreground network hiccups.
4. **Background/closed delivery → push notifications.** A held MQTT socket cannot
   deliver to a suspended app. If the device must receive something while
   backgrounded or closed (e.g. a "new order ready" alert), use **FCM (Android) /
   APNs (iOS)**, with MQTT used only while the app is in the foreground.

## One-line summary

**Foreground = we can be constantly connected. Background = expect to be dropped
after ~15 s (especially on iOS). Terminated = definitely offline via Last-Will.**
