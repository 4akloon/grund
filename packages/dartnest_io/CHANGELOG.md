## 0.1.0

Initial release.

- `IoAdapter`: serves an application on a `dart:io` `HttpServer`, streams
  bodies both ways, closes gracefully with a timeout and serves HTTPS with a
  `SecurityContext`.
