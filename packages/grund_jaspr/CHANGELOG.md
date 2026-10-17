## 0.3.0

- **Breaking:** requires Dart 3.13 (`sdk: ^3.13.0`).
- Static files answer `Accept-Encoding` with a precompressed `.br` or `.gz`
  sibling when one exists and is not older than the file; every static
  response carries `Vary: Accept-Encoding`.

## 0.2.0

Pages and sites replace the single root component.

- **Breaking:** `JasprModule(app:, imports:)` and `JasprPages` are removed;
  `JasprModule({config})` only supplies the rendering services. Pages are
  bindings declared in any module with `Pages.site<S>` (two bindings:
  spread it) and `Pages.under<S>`.
- **Breaking:** static files are served under `JasprConfig.staticPath`
  (`/static` by default) instead of the root; `JasprConfig.rootFiles` names
  the files (`robots.txt`, `favicon.ico`) that stay at the root.
- **Breaking:** a request whose last path segment has an extension outside
  `pageSuffixes` is a file request (a JSON 404 `file_not_found`, the page
  builder is not called), so a slug such as `v1.2` is not a page.
- New `JasprConfig` fields: `staticPath`, `rootFiles`, `sitemapChunkSize`
  (50000) and `sitemapCacheLifetime` (60 s).
- New public types: `PageSite` (path, `use`, `skippableHooks`, `shell`,
  `notFound`, `sitemapBaseUrl`), `Page`, `PageMeta`, `PageNav`,
  `PageHooks` (`skip` by exact hook type, `use`), `PageSitemap`,
  `PageExtension`, `PageCatalog` (`pagesOf`, `navOf`, `sitemapOf`,
  `invalidateSitemap`, `match`, `pagesWith`), `SitePage`, `PageMatch`,
  `NavItem`, `SitemapEntries` (`all`, `paged`), `SitemapEntry`,
  `SitemapUrl`, `SitemapChangeFrequency`, `BuildContext.pageMatch`, and the
  declaration and runtime errors (`SiteDeclarationError`,
  `PageDeclarationError`, `PageRuntimeError`).
- A page builder throws `NotFoundException` for an unknown parameter value:
  the answer is the site's 404 page. The fallback 404 page of a site goes
  through its hooks and ignores `skip`.
- Sitemaps: a site with `sitemapBaseUrl` serves `<site>/sitemap.xml` and
  chunked `<site>/sitemap/<n>.xml`, without the site's hooks.
- `PageMatch.meta` is the `PageMeta` of the matched page.
- A site path is checked when the site starts: `''` or `/segment[/segment]`
  of literals, no trailing `/`, not a `rootFiles` entry or under
  `staticPath` (`InvalidSitePathError`).
- `PageExtension.claim` runs after the hooks of the site, on file requests
  below the site; the extensions of pages with their own `hooks.use` are not
  asked, so a page-level guard is never bypassed (serve a variant of such a
  page through `respond`).
- Structural mistakes (a site without `/`, nested or duplicate paths, a
  forbidden hook skip, a reserved page path) fail at startup, and a hot
  reload that breaks one keeps the previous pages serving.
- Unmatched `GET`s get the HTML 404 page only below a site path (0.1.0: any
  unmatched `GET` did); elsewhere the JSON `route_not_found` stays.
- `JasprError` is now an `abstract base class`.
- New dependencies: `logging` and `path`.

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
