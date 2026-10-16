## 0.1.1

- Requires `grund_http` ^0.2.0.

## 0.1.0

Initial release.

- `IoAdapterModule`: global module that binds an `IoAdapter` as the
  `HttpAdapter` of `grund_http`.
- `IoAdapter`: serves an application on a `dart:io` `HttpServer`, streams
  bodies both ways, closes gracefully with a timeout and serves HTTPS with a
  `SecurityContext`.
