# Logging

grund logs through [`package:logging`](https://pub.dev/packages/logging). The
framework writes to named loggers and never configures `Logger.root` itself;
what is printed, and where, is up to the application.

## Loggers

| Logger | What it says |
| --- | --- |
| `grund.app` | starting, singletons created, started, shutting down, closed, reassembled, rollback warnings |
| `grund.modules` | `AuthModule initialized +2ms` after each module's `onInit` |
| `grund.routes` | `Mapped {GET, /tasks}` at start, `Unmapped {...}` on hot reload |
| `grund.http` | `HTTP server listening on localhost:8080`, `HTTP server closed`, unhandled errors (`SEVERE`) |
| `grund.access` | one line per request: `GET /tasks/1 200 12ms` |

## Attaching output

`App.run` attaches `LogOutput.console()` by default for the duration of the
run. `App.start` and `TestApp` attach nothing, so tests stay silent.

```dart
await App(root: AppModule()).run(log: LogOutput.json(level: Level.INFO));
```

- `LogOutput.console({level, color, sink})`: one line per record; color
  defaults to whether stdout supports ANSI escapes.
- `LogOutput.json({level, sink})`: one JSON object per line (`time`, `level`,
  `logger`, `message`, optional `error` and `stack`).
- `LogOutput.none()`: attaches nothing.

Without `sink`, records below `WARNING` go to stdout and the rest to stderr.
`attach()` returns a `LogSubscription`; `cancel()` stops the output and puts
the root level back.

## Your own sink

Pass `LogOutput.none()` and listen yourself:

```dart
Logger.root.level = Level.INFO;
Logger.root.onRecord.listen(myLogger.write);
await App(root: AppModule()).run(log: const LogOutput.none());
```

## The access log

Each answered request is one `INFO` line on `grund.access`, also for 404, 405
and error responses. Turn it off with
`HttpModule(config: HttpConfig(accessLog: false))`; nothing is built then. The
query string is never logged.

## Errors

An error that becomes a 500 response is logged as `SEVERE` on `grund.http`
(message `Unhandled error`) with the error and its stack trace; the response
body shows neither (unless `HttpConfig.debug`). To send them elsewhere (an
error tracker), subscribe to `Logger.root.onRecord` and pick the records of
that logger. A listener that throws fails on its own; the response is still
sent.
