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
    return p([Component.text('Visit number $count.')]);
  }
}

final class PublicSite extends PageSite {
  PublicSite(super.injector);

  @override
  Component shell(Component content) =>
      Document(title: 'Counter', body: content);
}

final class SiteModule extends Module {
  const SiteModule();

  // Pages see the providers of the module that declares their site.
  @override
  List<Module> get imports => const [CounterModule()];

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<PublicSite>(PublicSite.new),
    Pages.under<PublicSite>(
      (_) => [Page('/', build: (_) => const HomePage())],
    ),
  ];
}

final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(),
    IoAdapterModule(),
    JasprModule(),
    SiteModule(),
  ];
}

Future<void> main() => App(root: const AppModule()).run();
```

`package:jaspr/server.dart` and `package:grund/grund.dart` both declare
`Key`: in a file that imports both, hide Jaspr's (`hide Key`).

## Pages and sites

- A `Page` is a path (`/`, `/about`, `/projects/:slug`; literals and
  `:param`, never `*`), a `build` function and optional `PageMeta` (title,
  description, navigation entry, sitemap settings), `PageHooks` and
  `PageExtension`s. A builder throws `NotFoundException` for a parameter
  value it does not know, and the answer is the site's 404 page.
- A `PageSite` groups pages under a path prefix (`''` by default) with
  shared `use` hooks, a `shell` that wraps every page and a `notFound`
  page. Every site needs a `/` page; sites are independent, nested site
  paths and duplicate paths are errors at startup.
- Pages are bindings, declared in any module: `...Pages.site<S>(S.new)`
  (it returns two bindings) and `Pages.under<S>((injector) => [...])`. A
  module that declares pages under a site of another module imports the
  module that exports `Key<S>()`. The list function runs again on every hot
  reload.
- Hooks run in this order: the global ones of `HttpModule`, the site's
  `use`, the page's `hooks.use`. `PageHooks(skip: [...])` leaves a site
  hook out for one page, only for the types the site lists in
  `skippableHooks`. The fallback 404 page of a site goes through all its
  hooks and ignores `skip`.
- `JasprModule({config})` does not import `HttpModule`: the application
  imports it once, with its own hooks, middleware and configuration, and
  pages go through them like any route. API routes and pages share one
  router, so a literal segment beats a `:param` one.
- A component reads the request's call scope through `BuildContext`:
  `context.call<T>()` (throws when there is none), `context.maybe<T>()`,
  `context.injector`; the semantics are those of `HttpCtx`.
  `GrundScope.of(context)` is the `HttpCtx` itself: read cookies with
  `GrundScope.of(context).cookies`, not with Jaspr's `context.cookies`,
  which throws on a malformed `cookie` header. `context.pageMatch` is the
  matched page and its parameters (`null` in a 404 page).
- The response keeps everything Jaspr set: the status, every `set-cookie`
  (`context.setCookie`), other headers. An HTML page without a charset gets
  `text/html; charset=utf-8`; a page without `cache-control` gets
  `private, no-cache` (a page may depend on the session).
- A component that throws is a `PageRenderError`, answered as a 500
  `application/problem+json`. HTML error pages are not part of this
  release.
- `PageCatalog` (a global binding) lists the pages: `pagesOf<S>()`,
  `navOf<S>()` (`NavItem`s sorted by `order`, `label`, `path`),
  `sitemapOf<S>()`, `match(Uri)` and `pagesWith<T extends PageExtension>()`.

## Static files

Static files live outside the sites. `JasprConfig(staticDirectory: 'web')`
(the default) is served under `JasprConfig(staticPath: '/static')`:
`GET /static/styles.css` is `web/styles.css`, with its type and
`cache-control: no-cache`. Files that must sit at the root are listed in
`JasprConfig(rootFiles: ['robots.txt', 'favicon.ico'])` and come from the
same directory.

- The directory is resolved against the working directory: run the
  application from its package root. A directory that does not exist
  serves nothing; it is not an error.
- A path maps to a file only when every segment is a plain name: not empty,
  not starting with `.` (no `..`, no `.env`), without `/`, `\`, `:` or
  control characters, and the file, with symbolic links resolved, lies
  inside the directory.
- A request whose last path segment has an extension that is not a page
  suffix (`JasprConfig(pageSuffixes:)`, by default `html`, `htm` and
  `xml`) is a file request: a missing file is a 404 `file_not_found` and
  the page builder is never called. A slug such as `/projects/v1.2` or
  `/projects/node.js` is therefore not a page request, unless its
  extension is in `pageSuffixes`.

## Sitemap

A site with `sitemapBaseUrl` serves `<site>/sitemap.xml`, split into
`<site>/sitemap/<n>.xml` files of `JasprConfig.sitemapChunkSize` (50000)
addresses when it is larger. The sitemap is served without the site's
hooks, so a site with `use` and `sitemapBaseUrl` does not start
(`GuardedSiteSitemapError`). A page with parameters needs
`PageSitemap(entries: ...)` (`SitemapEntries.all` for small sets,
`.paged(count:, load:)` for big ones) or `PageSitemap(included: false)`; a
page with its own `hooks.use` is left out unless `included: true`. Entries
are cached for `sitemapCacheLifetime` (60 s by default), so a new row can
take up to that long to appear; `PageCatalog.invalidateSitemap()` clears
the cache. `<site>/sitemap.xml` and `<site>/sitemap/*` are reserved paths.

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
- Not in this release: Markdown pages, hydration (`@client`),
  `jaspr_builder`, HTML error pages.
