# Pages and sessions: Jaspr and grund_auth

One grund process can serve the JSON API and HTML pages rendered on the
server by [Jaspr](https://pub.dev/packages/jaspr), with one dependency
injection, one lifecycle and one cookie session:

- [`grund_jaspr`](../packages/grund_jaspr) renders pages: modules declare
  sites and pages as bindings, `JasprModule` serves them next to the API
  routes, and components read the call scope of their request
  (`context.call<T>()`).
- [`grund_auth`](../packages/grund_auth) keeps sessions: `Sessions.start`
  sets an `HttpOnly` cookie with an opaque token, and `SessionHook` puts
  the `CurrentUser` of every request with a live session in its call scope,
  where handlers and pages read it.

This release renders on the server only: there is no hydration (`@client`),
no client bundle and no `jaspr_builder`.

```sh
grund init --template fullstack my_site   # `--template api` is the default
cd my_site
dart pub get
grund dev        # http://localhost:8080; or: dart run grund_cli dev
```

## A page

A page is a path and a function that builds its content for the request.
The content is an ordinary Jaspr component; the site wraps it in a shell:

```dart
import 'package:grund_auth/grund_auth.dart' as auth;
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

final class HomePage extends StatelessComponent {
  const HomePage();

  @override
  Component build(BuildContext context) {
    final user = context.maybe<auth.CurrentUser>();
    final tasks = context.call<TasksService>().list();
    return Component.fragment([
      p([Component.text(user == null ? 'Signed out.' : 'Hi ${user.id}.')]),
      ul([for (final task in tasks) li([Component.text(task.title)])]),
    ]);
  }
}

Page(
  '/',
  build: (c) => const HomePage(),
  meta: const PageMeta(title: 'Tasks', nav: PageNav(label: 'Home')),
)
```

`context.call<T>()`, `context.maybe<T>()` and `context.injector` have the
semantics of `HttpCtx`: the bindings visible to the module that declares
the page's site, plus what hooks `set` for this request. `Component.text`
escapes its text, so a user name cannot inject markup. The `build` function
gets the `HttpCtx` too (`c.path.string('slug')`, `c.query`, `c.call<T>()`).

`Page` takes:

- `path`: literal segments and `:param` segments (`/`, `/about`,
  `/projects/:slug`); never `*`. The path is relative to the site.
- `build`: `FutureOr<Component> Function(HttpCtx c)`.
- `meta`: `PageMeta(title:, description:, nav:, sitemap:)`. `nav` is a
  `PageNav(label:, group: 'main', order: 0)`; a page without it is not in
  the navigation. `sitemap` is a `PageSitemap`, see
  [Sitemap and navigation](#sitemap-and-navigation).
- `hooks`: `PageHooks(skip:, use:)`, see [Sites](#sites).
- `extensions`: a list of `PageExtension`, see
  [Things to know](#things-to-know).

A builder that cannot find what the URL names throws `NotFoundException`
(from `package:grund_http/grund_http.dart`, as in an API handler):

```dart
Page(
  '/projects/:slug',
  build: (c) async {
    final project = await projects.find(c.path.string('slug'));
    if (project == null) throw const NotFoundException();
    return ProjectPage(project);
  },
)
```

The answer is the site's 404 page with status 404 (`PageSite.notFound`),
not the `application/problem+json` an API route would send.

`package:jaspr/server.dart` and `package:grund/grund.dart` both declare
`Key`. A file that imports both hides Jaspr's:
`import 'package:jaspr/server.dart' hide Key;`. A page file that imports
only `grund_jaspr` and `grund_auth` needs nothing hidden. `grund_auth` also
declares `CurrentUser`, which the example's API has its own of: import it
with a prefix when they meet.

## Sites

A site is a group of pages that share a path prefix, hooks and a page
shell. It is a class:

```dart
final class PublicSite extends PageSite {
  PublicSite(super.injector);

  @override
  Component shell(Component content) => Builder(
    builder: (context) => Document(
      title: context.pageMatch?.meta.title ?? 'Tasks',
      head: [link(href: '/static/styles.css', rel: 'stylesheet')],
      body: main_([content]),
    ),
  );

  @override
  Component notFound() => const Component.text('No page here.');
}
```

| Member | Meaning |
| --- | --- |
| `path` | `''` (default) or `/segment[/segment]`, the prefix of all its pages; no `:param`, `*` or trailing `/` (`InvalidSitePathError`). |
| `use` | `HookRef`s that run for every page of the site. |
| `skippableHooks` | The hook types a page may skip. |
| `shell(content)` | Wraps the content of every page, and the 404 page. |
| `notFound()` | The content for a request below `path` that no page matches. |
| `sitemapBaseUrl` | Switches the site's sitemap on, see [Sitemap and navigation](#sitemap-and-navigation). |

`context.pageMatch` is `null` in the 404 page; the title of the page that
rendered reaches the shell only through it.

Rules:

- Every site has a page at `/` (its root: for a site at `/blog`, the URL
  `/blog`). Without one the application does not start
  (`MissingSiteIndexError`).
- Sites are independent. Two sites on one path, or a site under the path
  of another, are errors (`DuplicateSitePathError`,
  `NestedSitePathError`); so are two pages of a site on the same path.
- A page path has literals and `:param`, never `*`
  (`InvalidPagePathError`). A literal beats a parameter.
- Hooks run in this order: the global hooks of the `HttpModule`, then the
  site's `use`, then the page's `hooks.use`.
- `PageHooks(skip: [SessionHook])` leaves a site hook out for one page. It
  is allowed only for the types the site lists in `skippableHooks`, and it
  matches the exact type: a subtype is another hook. Skipping a type that
  is not allowed, not among the site's hooks, or ambiguous is a declaration
  error at startup (`ForbiddenPageSkipError`, `UnknownPageSkipError`,
  `AmbiguousPageSkipError`).
- The fallback 404 page of a site (no page matched) goes through all of
  the site's hooks and ignores `skip`. A `NotFoundException` from a builder
  is rendered inside that page's own route, with the page's resolved hooks
  (`skip` applied).

## The module

Pages are bindings, so any module can declare them; `JasprModule` supplies
the rendering services and is imported once by the application.

```dart
final class HomeSiteModule extends Module {
  const HomeSiteModule();

  // The pages read what the module that declares their site can see.
  @override
  List<Module> get imports => const [TasksModule()];

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<PublicSite>(PublicSite.new),
    Pages.under<PublicSite>(
      (injector) => [
        Page('/', build: (_) => const HomePage(),
            meta: const PageMeta(title: 'Tasks')),
        Page('/login', build: (_) => const LoginPage(),
            meta: const PageMeta(title: 'Sign in')),
      ],
    ),
  ];
}

final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SessionHook>.type()]),
    IoAdapterModule(),
    SessionModule(config: SessionConfig(secure: false)), // dev over http
    JasprModule(),
    HomeSiteModule(),
  ];
}
```

- `Pages.site<S>(create)` returns **two** bindings (the site and its
  fallback route): spread it, `...Pages.site<S>(S.new)`.
- `Pages.under<S>((injector) => [...])` declares pages of the site `S`. The
  list function runs again after a hot reload, so an edited page list shows
  in the next response. A module can declare `Pages.under<S>` for a site of
  another module: it must import the module that exports `Key<S>()` (add
  `exports: [Key<S>()]` to the module that declares the site).
- `injector` resolves what the pages need at build time of the list; a
  page reads services per request through `c.call<T>()` or
  `context.call<T>()`.
- `JasprModule({config})` does not import `HttpModule`; the application
  imports it once, and its hooks and middleware run for pages too.
- API routes and pages share one router: a literal segment beats a
  `:param` one, so an API route `/tasks` stays the API's next to a page
  `/:slug`, and a page on exactly the path of an API route (say `GET /`) is a
  `DuplicateRouteError` at startup.
- Pages are `GET` (and `HEAD`) only. A path below a site that no page
  matches is the site's 404 page, not the `route_not_found` problem JSON;
  a path outside every site is the JSON 404 as before.
- Annotations cannot hold page functions: write the module that declares
  pages with the explicit API. It can sit next to annotated modules (the
  example's `WebModule` does).

`JasprConfig`:

| Field | Default | Meaning |
| --- | --- | --- |
| `staticDirectory` | `web` | Where the static files are read from. |
| `staticPath` | `/static` | The URL prefix of the static files. |
| `rootFiles` | `[]` | Files of the directory also served at the root. |
| `pageSuffixes` | `html`, `htm`, `xml` | Extensions a page URL may end with. |
| `liveReloadUrl` | from `GRUND_LIVE_RELOAD_URL` | The live reload script's event stream. |
| `sitemapChunkSize` | 50000 | Addresses per sitemap file. |
| `sitemapCacheLifetime` | 60 s | How long sitemap data is reused. |

A malformed value is a `JasprSetupError` at startup.

## Static files

Static files live outside the sites: the files of `web/` (next to
`pubspec.yaml`) are served under `JasprConfig.staticPath`, `/static` by
default, so `web/styles.css` is `GET /static/styles.css`. Run the
application from the package root (`grund dev` does);
`JasprConfig(staticDirectory:)` names another directory. Files that must
sit at the root, such as `robots.txt` and `favicon.ico`, are listed in
`JasprConfig(rootFiles: ['robots.txt', 'favicon.ico'])`; they are read from
the same directory. A page may not take a URL of the static files or of a
root file (`ReservedPagePathError`). A site path may not be a root file
either (`InvalidSitePathError`).

The static files carry no hooks. A `staticPath` inside the territory of a
guarded site (say `/admin/assets` with a site at `/admin`) is therefore
served to everyone: keep the static path outside the guarded sites.

Paths with dot segments, separators or links out of the directory are
never files. Static files are served with their type and
`cache-control: no-cache`.

A request whose last path segment has an extension that is not in
`pageSuffixes` is a file request: if the file does not exist the answer is
the JSON 404 `file_not_found`, and the page builder is never called. This
means a slug with a dot, such as `/projects/v1.2` or `/projects/node.js`,
is **not** a page request (unless its extension is a page suffix); keep
dots out of page parameters, or add the extension to `pageSuffixes`.

## Sitemap and navigation

`PageSite.sitemapBaseUrl` switches the sitemap of a site on:

```dart
@override
Uri? get sitemapBaseUrl => Uri.parse('https://example.com');
```

The site then serves `<site>/sitemap.xml` and, when it holds more than
`sitemapChunkSize` addresses, an index with `<site>/sitemap/<n>.xml`
chunks. These two paths are reserved in every site, whether or not it has
a `sitemapBaseUrl` (`ReservedPagePathError`).

- The sitemap is served **without the site's hooks**, so a site with `use`
  and a `sitemapBaseUrl` does not start (`GuardedSiteSitemapError`): put
  public pages in a site without hooks.
- A page without parameters is listed with its `PageSitemap(lastModified:,
  changeFrequency:, priority:)`.
- A page with `:param` needs `entries`, or `PageSitemap(included: false)`
  (`UndecidedPageSitemapError`; this applies only to a site with a
  `sitemapBaseUrl`). `SitemapEntries.all((injector) async =>
  [...])` loads the whole list at once, for small sets;
  `SitemapEntries.paged(count:, load:)` counts and loads by `offset` and
  `limit`, for big ones. A `SitemapEntry` carries the `params` of the path
  and an optional `lastModified`.
  `entries` on a page without parameters is an error
  (`UnusedPageEntriesError`); an entry whose parameters differ from the
  path's is a `PageEntriesMismatchError` at the sitemap request.
- A page with its own `hooks.use` is left out of the sitemap and the
  navigation unless `PageSitemap(included: true)`; `included: false` always
  leaves a page out.
- Entries and chunks are cached for `sitemapCacheLifetime`: a new database
  row can take up to 60 seconds to appear in the sitemap.
  `PageCatalog.invalidateSitemap()` clears the cache. A failing entries
  source gives a 500 on the sitemap request and a SEVERE log on
  `grund.http`, from the request boundary like any failing route. The page
  structure itself is never cached.

`PageCatalog` is a global binding that answers questions about the running
pages (it follows hot reloads; reading it before the application has
started is a `PageCatalogNotReadyError`):

```dart
final catalog = c.call<PageCatalog>();
final menu = catalog.navOf<PublicSite>(); // List<NavItem>, by order, label, path
```

- `pagesOf<S>()`: the `SitePage`s of the site `S` (the site, the `Page` and
  its full path).
- `navOf<S>()`: `NavItem(label:, path:, group:, order:)` of the pages with
  `meta.nav`, sorted by `order`, `label`, `path`; pages with parameters
  have no URL and are not listed.
- `sitemapOf<S>()`: a `Stream<SitemapUrl>` of the site's addresses.
- `match(Uri)`: the `PageMatch` (page and parameters) that would serve a
  URL, or `null` for a file request, a static URL or an unknown path.
- `pagesWith<T extends PageExtension>()`: the pages that carry an extension.

## Signing in

The page posts a form to an ordinary `HttpApi`; the handler checks the
credential itself (this release has no password or OAuth support), starts
the session and redirects with 303:

```dart
Route.post('/login', (c) async {
  final form = await c.form();
  final user = await accounts.verify(
    form.string('name', minLength: 1),
    form.string('password'),
  ); // yours
  await sessions.start(c, user.id);
  return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
}),
```

`c.form()` reads an `application/x-www-form-urlencoded` body into the
`Params` readers (a problem points at `/body/<name>`). `Sessions.start`
throws away the session the request came with and creates a new token, so a
cookie planted before the sign-in never becomes valid. The next `GET /`
passes `SessionHook`, and the page sees `context.maybe<CurrentUser>()`.
`Sessions.end(c)` signs out.

The cookie is `HttpOnly`, `SameSite=Lax`, `Path=/`, `Secure` unless
`SessionConfig(secure: false)` (development over plain `http` only), with
an absolute lifetime of 7 days. A handler can set cookies of its own next
to the session's (`SetCookie(...).toHeader()` on `c.response.headers` or in
a returned `HttpResponse`); every `set-cookie` reaches the browser.
`SetCookie` validates the names, values and attributes it builds (a `path`
must start with `/`, a positive `maxAge` must be at least one second); it
does not enforce a prefix policy, so a hand-built `__Host-` cookie is not
checked for `Secure` or `Path=/`.

In production run a compiled build (`dart compile exe`): `dart run` (JIT)
is not a product build, so the template's cookies are sent without
`Secure` there unless the application sets `secure: true`. Also name the
cookie `__Host-grund_sid` (`SessionConfig(cookieName: '__Host-grund_sid',
secure: true)`): the browser then accepts it only as `Secure` with
`Path=/` and no `Domain`, which defeats cookie tossing from a sibling
subdomain (with duplicate cookies the first one wins).

Cross-site form posts are refused: `SessionHook` answers an unsafe request
whose `sec-fetch-site` is another site, or whose `origin` is not the
`host` (more than one `origin` header is refused; the scheme is not
compared), with a 403 `cross_site_request`. The check is global once
`SessionHook` is registered: it runs on every route, so a token API that
a browser calls cross-origin with CORS gets a 403 on unsafe methods. Set
`SessionConfig(sameOrigin: false)` and register `SameOriginHook` only on
the cookie routes (the sign-in and sign-out). The
[`grund_auth` README](../packages/grund_auth/README.md) has every rule.

## Testing

`TestApp` and `TestClient` render pages without a socket:

```dart
test('the home page lists the tasks', () async {
  final app = await TestApp.start(root: const AppModule());
  addTearDown(app.close);

  final page = await TestClient.of(app).get('/');

  expect(page.status, 200);
  expect(page.headers['content-type'], 'text/html; charset=utf-8');
  expect(page.text, contains('<li>Read the grund README</li>'));
});
```

A form post is `client.request('POST', '/login', body: 'name=ann',
headers: {'content-type': 'application/x-www-form-urlencoded'})`; send the
session back with `headers: {'cookie': ...}`. The catalog is read from the
application: `app.injector<PageCatalog>().navOf<PublicSite>()`.

## Hot reload

`grund dev` serves pages like any route. An edited component shows in the
next response, without a restart (the process id stays). A page list
(`Pages.under`) is called again by the reassemble, so adding or removing a
page or a site in a reload works. A new field restarts the process, as
everywhere in [dev mode](dev-mode.md).

If the new set breaks a rule, the reload fails with that error, `dev`
prints it, and the application keeps serving. Two kinds of rule exist:

- Rules that need every site at once (a site without `/`, duplicate or
  nested site paths, a mismatched site type) are checked by the pages
  runner before it replaces its snapshot, and that runner reassembles
  before the HTTP one, so both the catalog and the routes keep the old
  set.
- Rules of one site or page (a forbidden `skip`, a reserved or invalid
  page path, an undecided sitemap, a duplicate page path) are checked when
  the HTTP server builds its route table; a failure there leaves the old
  routes serving. `JasprModule` is a global module, so the `pages` runner
  reassembles before the HTTP runner and has already replaced the
  catalog's snapshot: after such a failed reload `PageCatalog` describes
  the new pages while the routes are still the old ones. This is a
  development-time transient; the next successful reload makes them agree.
  (Only a global module that imports `HttpModule` turns the order round.)

At startup the same errors stop the application before it listens.

Open pages reload themselves: `dev` passes the URL of its event stream in
`GRUND_LIVE_RELOAD_URL`, and `JasprModule` adds a small script before the
last `</body>` of every HTML page, which reloads the page after every
reload or restart. Nothing is added in a product build, without the
variable, to other responses or to static files.

Run the application under `grund dev`, not under `jaspr serve`: Jaspr's
dev server runs `main` again on every change and serves its own client
build.

## Things to know

- **The first render prints a warning about `.client.dart`** to stdout
  (`[WARNING] ...`). A page that uses `Document` without a client script
  makes Jaspr print this one harmless notice at the first render of each
  process; it cannot be silenced and this release has no client
  components.
- **Read cookies with `GrundScope.of(context).cookies`**, not with Jaspr's
  `context.cookies`, which throws on a malformed `cookie` header.
- **A component that throws** is a 500 `application/problem+json`
  (`PageRenderError`); Jaspr prints the error to stderr. HTML error pages
  come later.
- **Pages are `private, no-cache`** unless a component sets
  `cache-control`: a page may depend on the session.
- **Dotted last segments are file requests** (see
  [Static files](#static-files)).
- **Page extensions** (`PageExtension`) are capabilities a page opts into
  through `Page(extensions:)`. After the hooks, `respond(c, match)` may
  answer instead of the page (an alternative representation of the same
  address) and `claim(c, uri)` may answer a file request (a last segment with an
  extension outside `pageSuffixes`) before the JSON 404 `file_not_found`;
  an unmatched page-like path such as `/blog/nope` goes to `notFound()`
  and never to `claim`. Both return `null` to let the default happen.
  `claim` runs after the hooks of the **site**, on file requests below the
  site; the extensions of pages with their own `hooks.use` are not asked, so
  a page-level guard is never bypassed. A layer that needs to serve a
  variant of such a page does it through `respond` on the page route. It is
  the extension point a Markdown layer would use; this release ships none.
- **Sessions live in memory**: they end with the process (a restart under
  `grund dev` signs everyone out) and are not shared between processes.
- **Jaspr is initialized once per process**, without isolates. Calling
  `Jaspr.initializeApp(useIsolates: true)` yourself is a
  `JasprSetupError`.
- **`grund_jaspr` does not depend on `grund_auth`**: pages see
  `CurrentUser` only because `SessionHook` sets it in the call scope.
