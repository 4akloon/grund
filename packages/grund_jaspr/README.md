# grund_jaspr

Server-side rendered [Jaspr](https://pub.dev/packages/jaspr) pages in a
grund application: one process serves the API and the pages, with one
dependency injection, one lifecycle and the same hooks.

```dart
import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;

final class HomePage extends StatelessComponent {
  const HomePage();

  @override
  Component build(BuildContext context) {
    // VisitCounter is a singleton that CounterModule exports.
    final count = context.call<VisitCounter>().visit();
    return Document(body: p([Component.text('Visit number $count.')]));
  }
}

final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(),
    IoAdapterModule(),
    JasprModule(app: HomePage.new, imports: [CounterModule()]),
  ];
}

Future<void> main() => App(root: const AppModule()).run();
```

`package:jaspr/server.dart` and `package:grund/grund.dart` both declare
`Key`: in a file that imports both, hide Jaspr's (`hide Key`). The example
tab has the whole program.

## Pages

- `JasprModule(app:)` serves `GET /` and `GET /*` (and `HEAD` with them)
  below every API route: a literal or `:param` segment of an API wins over
  `*`, so `/tasks/1` stays the API's and `/about` is a page.
- `app` is called for **every request** and builds the root component;
  route between pages in it (with `context.url`, or `jaspr_router`). Under
  `grund dev` an edited component shows in the next response.
- `JasprModule` does not import `HttpModule`: the application imports it
  once, with its own hooks, middleware and configuration, and pages go
  through them like any route (a global hook runs before a page is built).
- A component reads the request's call scope through `BuildContext`:
  `context.call<T>()` (throws when there is none), `context.maybe<T>()`,
  `context.injector`; the semantics are those of `HttpCtx`. The bindings
  visible there are the exports of `JasprModule(imports:)` and of global
  modules, plus what hooks `set` for the request (`grund_auth`'s
  `CurrentUser`). `GrundScope.of(context)` is the `HttpCtx` itself: read
  cookies with `GrundScope.of(context).cookies`, not with Jaspr's
  `context.cookies`, which throws on a malformed `cookie` header.
- The response keeps everything Jaspr set: the status, every `set-cookie`
  (`context.setCookie`), other headers. An HTML page without a charset gets
  `text/html; charset=utf-8`; a page without `cache-control` gets
  `private, no-cache` (a page may depend on the session). `content-length`
  is left to the adapter.
- A component that throws (Jaspr prints the error and answers 500) is a
  `PageRenderError`, answered like any failure as a 500
  `application/problem+json`. HTML error pages are not part of this
  release.

## Static files

`JasprConfig(staticDirectory: 'web')` (the default) serves the files of
`web/` before pages: `GET /styles.css` is `web/styles.css` with its type
and `cache-control: no-cache`.

- The directory is resolved against the working directory: run the
  application from its package root. A directory that does not exist
  serves nothing; it is not an error.
- A path maps to a file only when every segment is a plain name: not empty,
  not starting with `.` (no `..`, no `.env`), without `/`, `\`, `:` or
  control characters (a percent-encoded `%2F` arrives decoded in a
  segment), and the file, with symbolic links resolved, lies inside the
  directory. Anything else is not a file, and the path is a page or a 404.
- A path whose extension is not a page suffix
  (`JasprConfig(pageSuffixes:)`, by default `html`, `htm` and `xml`) and
  that is not a file is a 404 `file_not_found`, not a page.

## Live reload

Under `grund dev`, open pages reload themselves after every reload or
restart of the application. `dev` passes the URL of its event stream in
`GRUND_LIVE_RELOAD_URL`, and `JasprModule` then adds a small script before
the last `</body>` of every HTML page it renders. Nothing is added in a
product build (`dart compile exe`), without the variable, to responses that
are not UTF-8 HTML, or to static files. `JasprConfig(liveReloadUrl:)` sets
the URL by hand.

## Things to know

- Jaspr's process-wide state is initialized once, in `onInit`, without
  isolates; several applications in one process (tests) share it. A
  `Jaspr.initializeApp(useIsolates: true)` of your own is a
  `JasprSetupError`: a page reads the call scope of its request, which
  another isolate cannot reach.
- The first render prints a `[WARNING]` about a missing `.client.dart`
  file to stdout. A page that uses `Document` without a client script makes
  Jaspr print this one harmless notice at the first render of each process;
  it cannot be silenced, and there are no client components in this
  release.
- Do not run the application under `jaspr serve`; use `grund dev`.
- Not in this release: hydration (`@client`), `jaspr_builder`, HTML error
  pages.
