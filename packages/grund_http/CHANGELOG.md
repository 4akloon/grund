## 0.1.0

- Initial release.
- Logging: an unhandled error is logged as `SEVERE` on `grund.http` (error and
  stack trace); subscribe to `Logger.root.onRecord` to forward it. Routes, the listener and
  shutdown are logged, and `HttpConfig.accessLog` (default `true`) logs each request on
  `grund.access`.
