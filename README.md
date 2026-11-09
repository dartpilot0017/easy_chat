# easy_chat: live demo of easy_socket

A Flutter chat app and a small Dart server that show off
[easy_socket](https://pub.dev/packages/easy_socket). The app has no
websocket code beyond `on`, `emit` and a few options.

**Try it:** https://easy-chat-app.onrender.com
(Open it in two tabs or send it to a friend to chat with each other.)

## What to try

| Feature | How to see it |
|---|---|
| Message format auto-detection | Pick a format on the join screen. The server speaks it; the app code is the same for all three. The socket log shows the raw frames. |
| Auth token per connection | Every connection sends `?token=` (shown as `***` in the log). Turn on **Send a wrong token** to see the server refuse it with code 4401: no retry loop. |
| `onConnected` rejoin | Joining the room happens in `onConnected`, so it runs again after every reconnect. |
| Auto-reconnect | Playground → **Drop my connection**. The server hangs up; the app reconnects and rejoins by itself. |
| Offline queue | Playground → **Go offline**, send a few messages (they show "sending…"), then **Go online**. They're delivered in order. |
| Refused connections | Playground → **Get kicked**. The server closes with 1008 and easy_socket stops retrying until you press **Reconnect**. |
| Heartbeat | Every 20 seconds the app pings and the server answers `pong` (see the log). Dead connections are detected and replaced. |
| Typing, rooms, history, presence | Just use the chat. |

On a narrow screen the playground opens from the flask icon in the top bar.

**About hosting behind a proxy:** Render's proxy doesn't pass websocket close
codes on, and keeps a closed connection open for about 20 seconds. So before
the server closes a connection itself (drop, kick, wrong token), it sends a
`closing` event with the code and reason, and the app acts on that straight
away. Run locally, the real close codes arrive too, and easy_socket handles
them on its own.

## Run it locally

```bash
cd server && dart run bin/server.dart
```

```bash
cd app && flutter run -d chrome
```

## How it's hosted

- **Server:** Render free web service, built from `server/Dockerfile`
  (`render.yaml`). It needs `CHAT_TOKEN=demo`. Render's free plan sleeps
  after 15 minutes without traffic; an UptimeRobot HTTP monitor on the
  server URL every 5 minutes keeps it awake.
- **App:** a free Render static site serving the `web-build` branch.
  `.github/workflows/web.yml` builds the Flutter web app on every push to
  `main` and publishes the files to that branch (Render's build machines don't
  have Flutter). Set the repository variable `SERVER_URL` to the server's
  `wss://` address.
