## 0.1.0

Initial release.

- `JasprModule(app:, imports:, config:)`: serves server-side rendered Jaspr
  pages on `GET /` and `GET /*` below the application's API routes, through
  its `HttpModule` hooks and middleware; the root component is built for
  every request.
- `GrundScope` and the `BuildContext` extension `GrundContext`:
  `context.call<T>()`, `context.maybe<T>()` and `context.injector` read the
  call scope of the request being rendered.
- The response keeps Jaspr's status and headers, every `set-cookie`
  included; HTML gets a UTF-8 charset and pages `private, no-cache` unless
  the page set its own.
- Static files from `JasprConfig.staticDirectory` (`web/`), refusing dot
  segments, separators and paths that leave the directory; a path with an
  extension that is not a page suffix and not a file is a 404.
- A page that fails to render is a `PageRenderError` (a 500
  `application/problem+json`).
- Under `grund dev` (`GRUND_LIVE_RELOAD_URL`), HTML pages get a script that
  reloads them after every reload or restart; never in product builds.
