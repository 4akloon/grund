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

Pages are rendered on the server. Interactivity comes from HTML fragments
that the server sends and htmx swaps in (see
[Fragments and htmx](#fragments-and-htmx)); where typed logic must run in
the browser, a Jaspr component can be hydrated (see
[Client components](#client-components)). There is no `@client` annotation
and no `jaspr_builder` yet.

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
  `/projects/:slug`); never `*`, and a parameter name is an identifier
  (`:slug`, not `:slug.md`: alternates are declared with `PageAlternate`).
  The path is relative to the site.
- `build`: `FutureOr<Component> Function(HttpCtx c)`.
- `meta`: `PageMeta(title:, description:, nav:, sitemap:)`. `nav` is a
  `PageNav(label:, group: 'main', order: 0)`; a page without it is not in
  the navigation. `sitemap` is a `PageSitemap`, see
  [Sitemap and navigation](#sitemap-and-navigation).
- `hooks`: `PageHooks(skip:, use:)`, see [Sites](#sites).
- `alternates`: other representations of the page, such as Markdown, see
  [Alternate representations](#alternate-representations).

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
| `baseUrl` | The public origin (`https://example.com`). Switches the site's sitemap on and makes absolute URLs possible, see [Addresses](#addresses-base-url-and-trailing-slash) and [Sitemap and navigation](#sitemap-and-navigation). |
| `trailingSlash` | `TrailingSlash.never` (default), `always` or `ignore`, see [Addresses](#addresses-base-url-and-trailing-slash). |
| `requiredAlternates` | Media types every page must have an alternate of (`['text/markdown']`), see [Alternate representations](#alternate-representations). |
| `files` | Generated text files such as `/robots.txt` and `/llms.txt`, see [Site files](#site-files). |

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

## Fragments and htmx

A fragment is a piece of HTML without a document around it: the answer to a
request that htmx swaps into a page. `Fragments.respond` renders any Jaspr
component under the same call scope as a page (`context.call<T>()` works),
with no shell, no live reload script and no Jaspr client script:

```dart
Route.post('/fragments/tasks', (c) async {
  final title = (await c.form()).stringOrNull('title') ?? '';
  try {
    tasks.create(CreateTask.fromJson({'title': title}));
  } on FormatException catch (refusal) {
    // The form comes back in place, with the message and what was typed.
    return Fragments.respond(
      c,
      TaskPanel(tasks: tasks.list(), editable: true, draft: title,
          error: refusal.message),
      status: 422,
    );
  }
  return Fragments.respond(
    c,
    TaskPanel(tasks: tasks.list(), editable: true),
    status: 201,
  );
}),
```

The handler's module must import `JasprModule`; otherwise `respond` throws
`JasprSetupError`. A component that throws is a `PageRenderError`. The
response is `text/html` with `cache-control: private, no-cache`.

To use htmx, serve the script as a static file and load it in the shell of
the site (the example vendors htmx 2.0.11 in `web/vendor/`). htmx 2 does
not swap `4xx` and `5xx` answers by default, so a refused form (`422`)
would show nothing; say which codes to swap in an `htmx-config` meta:

```dart
static const _htmxConfig =
    '{"responseHandling":['
    '{"code":"204","swap":false},'
    '{"code":"[23]..","swap":true},'
    '{"code":"422","swap":true},'
    '{"code":"[45]..","swap":false,"error":true}]}';

// in PageSite.shell:
head: [
  meta(name: 'htmx-config', content: _htmxConfig),
  script(src: '/static/vendor/htmx.min.js', defer: true),
],
```

Elements then carry `hx-post`, `hx-delete`, `hx-target` and `hx-swap`
attributes. The example's `TaskPanel` and `TaskFragments` show the whole
loop: a form that posts, a `422` that re-renders the form with the message,
a delete button, and guests getting `401`.

**Things to know**

- A failed request whose status is not swapped (`401`, `403`, `404` with
  the configuration above) shows the user nothing: htmx only raises an
  `htmx:responseError` event. Swap the codes you want shown (add them to
  `responseHandling`) or listen for the event and show a message.
- CSRF: `SessionHook` from `grund_auth` (with `SessionConfig.sameOrigin`,
  on by default; it applies `SameOriginHook`) refuses a cross-site write with
  `403 cross_site_request`. A same-origin XHR from htmx passes, and so does
  a request without browser headers (curl); there is no token to add to the
  forms.
- htmx gives no offline work and no instant local state: every change is a
  round trip.

**Choosing the tool**

- Server fragments for everything whose truth lives on the server: CRUD,
  forms, lists, search, navigation.
- Local state (a few lines of JS, or Alpine) for pure interface state, such
  as tabs, menus and dialogs, that must react within about 50 ms or work
  without the network.
- A Jaspr island (see [Client components](#client-components)) for typed
  logic that is shared with the server or is not trivial. An island inside a
  fragment that is swapped in later is not hydrated: the client reads the
  island markers once, at start. Put islands on the page and let the
  fragment update the server-rendered content around them.

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

Every static response carries a weak `ETag` and `Last-Modified`. A request
with a matching `If-None-Match` (or, without it, a not-newer
`If-Modified-Since`) is answered `304` without a body. The `ETag` differs
per encoding, and `cache-control: no-cache` means a browser revalidates
each time, so unchanged files cost a `304`.

`grund_jaspr` does not compress files; it serves compressed files you
prepared. Next to `app.js` put `app.js.br` and/or `app.js.gz`
(`brotli -k app.js`, `gzip -k -9 app.js`, a build step or a CDN does it):

- the encoding follows `Accept-Encoding`, preferring `br`, then `gzip`,
  then the original; `q=0` forbids an encoding;
- a sibling is used only if it is a regular file inside the static
  directory (a link that leaves it is ignored) and is not older than the
  original, so a stale `.br` after an edit is never served;
- the answer has `Content-Encoding`, the type of the original file and
  `Vary: Accept-Encoding`; every static response has `Vary`, compressed or
  not;
- a direct request for `app.js.br` is an ordinary file request.

A request whose last path segment has an extension that is not in
`pageSuffixes` is a file request: if the file does not exist the answer is
the JSON 404 `file_not_found`, and the page builder is never called. This
means a slug with a dot, such as `/projects/v1.2` or `/projects/node.js`,
is **not** a page request (unless its extension is a page suffix); keep
dots out of page parameters, or add the extension to `pageSuffixes`.

## Client components

A client component (an island) is a Jaspr component that the server renders
and the browser then takes over: it keeps its state and handles events
without a request. Everything else on the page stays plain HTML. Use it by
the rule in [Fragments and htmx](#fragments-and-htmx): a server fragment
when the truth lives on the server, local state for pure interface state,
an island for typed or non-trivial client logic.

**Register the components.** One file, shared by the server and the
browser, lists them. It imports only
`package:grund_jaspr/client_components.dart`, which depends on nothing but
`package:jaspr/jaspr.dart` (the main library pulls in `dart:io`, which the
browser cannot compile):

```dart
// lib/clients.dart
import 'package:grund_jaspr/client_components.dart';
import 'src/web/counter.dart';

const clients = ClientComponents([
  ClientComponent<Counter>(
    'counter',
    encode: Counter.toParams,
    decode: Counter.fromParams,
  ),
]);
```

- The name matches `[a-z0-9_-]+` and is written into the page. `decode`
  builds the component in the browser from the parameters; `encode` gives
  the parameters on the server. Without `encode` the component has no
  parameters.
- Write the type argument (`ClientComponent<Counter>`); without it the type
  is inferred as `Component` and the list has a problem. A duplicate name,
  two entries for one type and an unusable name are problems too: the
  server refuses to start with a `JasprSetupError` that lists them, and the
  browser throws a `StateError`.
- The registered type is the exact runtime type: a subclass of `Counter` is
  not an island and renders as ordinary HTML.
- The parameters travel as JSON in the page, so they must be JSON values
  (numbers, strings, booleans, lists and maps of them). Anything else makes
  the render fail with a `500` problem response.
- The component is compiled for the web: its imports (and theirs) must not
  reach `dart:io`, `package:jaspr/server.dart` or the server side of your
  application. A violation shows as a compiler error from `grund bundle`.

**Turn it on.** Give the list to the module, and remove any
`Jaspr.initializeApp(options: ...)` call of your own from `main`:

```dart
const JasprModule(config: JasprConfig(clients: clients))
```

Then use the component in a page like any other (`const Counter(start: 5,
label: 'Tasks')`). The server writes a marker `<!--@counter data=...-->`
around its HTML, and the page gets the script of the bundle.

**The browser entry.** `lib/main.client.dart` is the file `grund bundle`
compiles:

```dart
import 'package:grund_jaspr/client.dart';
import 'clients.dart';

void main() => GrundClient.run(clients);
```

`GrundClient.run` hydrates every marker it finds once, at start.

**Build the bundle.**

```sh
dart run grund_cli bundle        # web/client/main.client.dart.js
```

`bundle` always makes the production build: `dart compile js -O2
-Djaspr.flags.release=true`, with no source maps (`/static` serves every
file of `web/`, and a map would publish your sources). There is no
`--release` flag and no `-O0`. Options: `--entry <file>` (default
`lib/main.client.dart`; the output name is the entry's name plus `.js`, and
with `JasprConfig.clients` the pages load `main.client.dart.js` only, so the
entry file must be named `main.client.dart`: `--entry lib/app.client.dart`
writes `app.client.dart.js`, which no script tag references and the startup
warning reports; an explicit `--entry` that is not a file exits `64`),
`--output <dir>` (default `web/client`; give the directory under your
`JasprConfig.staticDirectory` plus `/client` when you changed it, because
the CLI does not read the runtime configuration) and `--directory`/`-C`.
It replaces the old `main.client.dart.js*` files of the output directory,
including stale compressed siblings; it compiles in
`.dart_tool/grund_bundle/build_*` and moves only the bundle files. Without
the default entry it prints a message and exits `0`. It needs the Dart VM: an AOT-compiled `grund` cannot run
`dart compile js`, so use `dart run grund_cli` or `dart pub global run
grund_cli`. Add `web/client/` to `.gitignore`; the scaffold of `grund init
--template fullstack` does.

`bundle` does not compress. `/static` serves precompressed siblings (see
[Static files](#static-files)), so compress after building:

```sh
gzip -9k web/client/main.client.dart.js
brotli -k web/client/main.client.dart.js
```

A sibling older than the bundle is ignored, so run these after every
`bundle`.

**The script is on pages with islands only.** The bundle's script tag is
`<script src="static/client/main.client.dart.js" defer>`, a relative
address built from `staticPath`. A page without a marker gets no script,
and a fragment never does. Jaspr renders the `src` relative to the base of
the document: with Jaspr's default `<base href="/">` it stays
`static/client/main.client.dart.js` and resolves to `/static/...` from any
page; with no `<base>` tag it renders `/static/client/main.client.dart.js`.
Either works. A `<base>` with another value breaks the address, so a page
with islands needs a `<base>` that is absent or `/` (see [Things to
know](#things-to-know)).

**Under `grund dev`.** `dev` builds the bundle before it serves (`-O1`
with source maps, never `-O0`), and again, in parallel with the hot
reload, after every change of a `.dart` file that generates cleanly;
changes during a build merge into one more build. A failed build is printed
and the previous bundle stays; the live reload is still sent, because the
page needs the server changes. When you stop `dev`, a build in flight
finishes without printing anything and no further build starts. Changing the browser entry is `--client-entry <file>` (default
`lib/main.client.dart`; `dev --entry` is the server entry, an alias of
`--target`); `--output` is as for `bundle`. A `--client-entry` that is not a
file stops `dev` with exit code 64. Whether the package has a
browser entry is decided once, when `dev` starts: add `main.client.dart`
and restart `dev`.

A hot reload of a component's body (and of its `encode`/`decode`) works.
It does not run `onInit` again and keeps the module's singletons, so a
change of `JasprConfig` or of the `clients` list is not picked up: restart
`grund dev`, or hot restart it with `R`.

**A missing bundle** is a `WARNING` on the logger `grund.jaspr` at
startup: `JasprConfig.clients` is set and
`<staticDirectory>/client/main.client.dart.js` is not a file there (for
example `bundle` was not run). The server starts anyway, since tests and
deployments that serve the bundle from a CDN do not keep it beside the
server, and the pages are served without hydration. The reverse is not
detected: a `lib/main.client.dart` with no `JasprConfig.clients` hydrates
nothing. An empty `ClientComponents([])` counts as no clients: the pages get
no script and the warning is not logged.

**One Jaspr state per process.** Jaspr keeps its server options in
process-wide state. `JasprModule` installs the client options there itself
and refuses (with a `JasprSetupError`) `useIsolates: true` and options that
you installed yourself with clients or styles. A hot reload and the next
`TestApp` replace its own options; the options are put back when the module
shuts down. Two applications alive in one process at the same time with
different `clients` lists are not detected: the later one wins.

**Limits.**

- An island inside a fragment that htmx swaps in after the page loaded is not
  hydrated: the client looks for markers once, at start. Put islands on the
  page and let the fragment update the server content around them (the
  example's counter sits next to the task list, and adding a task does not
  reset it).
- There is no lazy loading of components; the bundle holds all of them.
- The script is the whole bundle (about 35 KB with brotli for a
  counter); a page with no island does not load it.

**Check it in a browser.** The automatic tests check the markup and the
compilation, not the running script. By hand, with the scaffold or the
example:

1. `dart run grund_cli bundle` in the package (`example/` or a package made
   by `grund init --template fullstack`).
2. Run the server (`dart run grund_cli dev`, or the application as in its
   README) and open the home page.
3. Press the counter's buttons: the number changes and the network panel
   shows no request.
4. View the page source: the island is wrapped in a `<!--@counter ...-->`
   marker, and the `<script src="...main.client.dart.js">` tag is there.
   Open a page without islands (or the 404 page) and a fragment response:
   neither has the script tag.
5. Add a task through the htmx form: the list updates and the counter keeps
   its value.

## Addresses: base URL and trailing slash

`PageSite.baseUrl` is the public origin of the site. It must be `http` or
`https`, have a host, and have no path (or just `/`), query, fragment or
user info; anything else stops the application before it starts
(`InvalidSiteBaseUrlError`). Without it the site has no sitemap and no
absolute URLs, and the canonical `Link` header of alternates is not sent.
The framework never takes the origin from the `Host` header, which the
client controls.

`PageSite.trailingSlash` says how page URLs end:

| Value | `/about/` | `/about` |
| --- | --- | --- |
| `never` (default) | 308 to `/about` | 200 |
| `always` | 200 | 308 to `/about/` |
| `ignore` | 200 | 200 |

- The redirect is `308` (the method and body survive) with
  `cache-control: max-age=3600` (`private, max-age=3600` when the route has
  hooks, so a shared cache cannot answer a client the hooks did not check),
  and the query string is kept as sent.
  Every empty segment is dropped, not only the last slash: `/about//` and
  `///about` both redirect to `/about`, and `//evil.test/x/` redirects to
  `/evil.test/x`, never to a URL on another host. A `%2F` stays encoded.
- It runs after the hooks of the site, so a hook that refuses (a guest on a
  protected page) answers first, and before the page builder. Page
  URLs get the canonical form of the policy (a slash is added only under
  `always` and removed under `never`, except for a dotted last segment,
  below). Alternate, site file and sitemap URLs
  only ever lose a trailing slash, never gain one (`/robots.txt/` and
  `/about.md/` answer 308 to the URL without it). A file request (a last
  segment with a dot that is not a page suffix, no trailing slash, such as
  `/logo.png`) is not redirected and not served by a page, and neither are
  static files or the fallback 404 (`/feed.xml` is a page request: `xml` is
  a default page suffix). `always` adds no slash to `/` itself or to a last
  segment with an extension; the root of a prefixed site is not exempt
  (`/blog` answers 308 to `/blog/`).
- With `ignore`, links and the sitemap use the declared path, without a
  slash.

`PageMatch` spells an address the way the site does, so you do not build
URLs by hand:

```dart
final match = PageMatch(page: sitePage, params: {'slug': 'grund'});
match.path;        // '/projects/grund' (percent-encoded, per trailingSlash)
match.url;         // https://example.com/projects/grund, or null without baseUrl
match.alternatePath('text/markdown'); // '/projects/grund.md', or null
```

A canonical address never leads to a file request. A page whose last
segment would have an extension that is not a page suffix without the slash
(a `:slug` value such as `v1.2`) keeps the trailing slash under every
policy, because `/v1.2` is a file request and answers 404: the page is at
`/v1.2/`, which is also what `path`, `url`, the sitemap, the navigation and
the canonical `Link` use, and `/v1.2/` is served instead of redirected.

```dart
PageMatch(page: sitePage, params: {'slug': 'v1.2'}).path; // '/projects/v1.2/'
```

`path` and `alternatePath` throw `ArgumentError` for a missing parameter
and for a value that is empty, `.` or `..`. The same dot segments answer
404 on the request side: `..` is normalized by URI parsing before routing
(`/projects/..` is `/`), and a `.` slug answers 404 (the site's 404 page on a
page and on the negotiated URL, the problem 404 on the alternate's own
URL).

## Alternate representations

A page can have other representations of the same content, the usual one
being Markdown for agents. Declare them on the page:

```dart
Page(
  '/projects/:slug',
  build: (c) async => ProjectPage(await projects.find(c.path.string('slug'))),
  alternates: [
    PageAlternate.markdown((c, match) async {
      final project = await projects.find(match.params['slug']!);
      if (project == null) throw const NotFoundException();
      return '# ${project.name}\n\n${project.summary}\n';
    }),
  ],
)
```

`PageAlternate(mediaType:, suffix:, build:)` is the general form;
`PageAlternate.markdown` is `text/markdown` at `.md`. The builder returns
the text and throws `NotFoundException` for a parameter it does not know,
which answers the site's 404 page when the alternate was chosen by `Accept`
on the page URL, and the `application/problem+json` 404 on the alternate's
own URL. The suffix matches `^(\.[a-z0-9]+)+$`.

An alternate has **its own URL**: the page URL plus the suffix
(`/projects/grund.md`; the root page of a site at `/blog` gets
`/blog/index.md`). It runs the same hooks as the page, with the same
`skip`, so a guest gets the same refusal on `/projects/x.md` as on
`/projects/x`.

The page URL also **negotiates on `Accept`**. A request gets an alternate
when its `Accept` header names that media type itself (not through `*/*`)
with a quality at least that of `text/html`; the best quality wins and a tie
goes to the order of declaration, so `text/html, text/markdown` gets
Markdown and `text/markdown;q=0.1, */*` gets HTML. A missing, blank or
unreadable header gets HTML, and there is no `406`. (`AcceptHeader` in
`grund_http` does the reading, see [HTTP APIs](http-and-hooks.md).)

- Every negotiated response carries `Vary: Accept` (merged with a `vary`
  your hook set, `*` wins) and, on the HTML, a `Link` with
  `rel="alternate"` to the alternate URL.
- An alternate is served as `<mediaType>; charset=utf-8` with
  `cache-control: private, no-cache` unless `c.response` already set its
  own. On its **own URL** and with a `baseUrl` it also sends
  `Link: <page URL>; rel="canonical"` (the response negotiated on the page
  URL needs none: that URL is the canonical one). The canonical is the
  **page** URL, so search engines index the page and not
  the `.md` copy. There is no `noindex` by default; a builder that wants one
  sets it itself: `c.response.headers.set('x-robots-tag', 'noindex')`.
- A cache or CDN in front of the application must key the page URL on
  `Accept` (it honors `Vary`), or the Markdown reaches a browser.
- `HEAD` gets the headers of `GET`; dropping the body is the adapter's job.
- `PageSite.requiredAlternates` makes an alternate mandatory: a page of the
  site without an alternate of each listed media type does not start
  (`MissingPageAlternateError`). Two alternates of a page on one suffix or
  media type, an alternate of `text/html`, and a suffix whose extension is
  in `pageSuffixes` are errors too (`InvalidPageAlternateError`); so is an alternate URL
  that another route already has (`DuplicateRouteError`).

Markdown for agents also wants an index, `llms.txt`, which is a
[site file](#site-files) built from the catalog:

```dart
SiteFile(
  '/llms.txt',
  mediaType: 'text/plain',
  build: (c) async {
    final catalog = c.call<PageCatalog>();
    final lines = ['# Example', ''];
    await for (final url in catalog.sitemapOf<PublicSite>()) {
      final match = catalog.match(url.location);
      final markdown = match?.alternatePath('text/markdown');
      if (markdown != null) {
        lines.add('- ${url.location.resolve(markdown)}: ${match!.meta.title}');
      }
    }
    return lines.join('\n');
  },
)
```

`url.location` is absolute (the site's `baseUrl` is applied), so the link
is too. For pages without parameters
`catalog.pagesOf<PublicSite>()` and `PageMatch(page:, params: const {})`
give the same without the sitemap.

## Site files

`PageSite.files` serves generated text at fixed paths of the site, such as
`/robots.txt`, without a file on disk (`JasprConfig.rootFiles` serves a
file from the static directory):

```dart
@override
List<SiteFile> get files => [
  SiteFile(
    '/robots.txt',
    mediaType: 'text/plain',
    build: (c) => 'User-agent: *\nAllow: /\nSitemap: https://example.com/sitemap.xml\n',
  ),
];
```

- The builder gets the `HttpCtx` and returns the text (sync or async). The
  response is `<mediaType>; charset=utf-8` and `cache-control: private,
  no-cache` unless `c.response` set its own.
- A file runs the hooks of the site, like a page. For a public
  `robots.txt`, keep it in a site without guarding hooks.
- The path is relative to the site; the site `/docs` serves `/docs/llms.txt`.
- A file is a territory of its own: a **literal site file path wins over a
  parametric page**, so `/projects/x` beats `/projects/:slug`, as a literal
  `/projects/new` beats the parameter in any router. The trailing slash policy
  only removes a slash from its URL (`/robots.txt/` is a 308 to
  `/robots.txt`).
- A path the framework cannot serve is a startup error,
  `InvalidSiteFileError`, with the path and the reason: no leading `/`,
  the site root `/`, a trailing slash, an empty segment (`//`), `:` or
  `*`, `?`, `#`, `%` or a `.`/`..` segment (no request can match them), a
  media type that is not lower case `type/subtype`, a reserved path (the
  static directory, the sitemap, a `rootFiles` file). Two files on one
  path, or a file on the own URL of an alternate, are a
  `DuplicateRouteError`.

## Sitemap and navigation

`PageSite.baseUrl` switches the sitemap of a site on:

```dart
@override
Uri? get baseUrl => Uri.parse('https://example.com');
```

The site then serves `<site>/sitemap.xml` and, when it holds more than
`sitemapChunkSize` addresses, an index with `<site>/sitemap/<n>.xml`
chunks. These two paths are reserved in every site, whether or not it has
a `baseUrl` (`ReservedPagePathError`).

- The sitemap is served **without the site's hooks**, so a site with `use`
  and a `baseUrl` does not start (`GuardedSiteSitemapError`): put
  public pages in a site without hooks.
- A page without parameters is listed with its `PageSitemap(lastModified:,
  changeFrequency:, priority:)`.
- A page with `:param` needs `entries`, or `PageSitemap(included: false)`
  (`UndecidedPageSitemapError`; this applies only to a site with a
  `baseUrl`). `SitemapEntries.all((injector) async =>
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

`pagesOf<S>()` and `sitemapOf<S>()` list the addresses to check or to
publish; `PageMatch.path`, `url` and `alternatePath` spell one, see
[Addresses](#addresses-base-url-and-trailing-slash).

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
`client.head('/')` sends a `HEAD`; the test client keeps its body, a real
server drops it. `client.get('/', headers: {'accept': 'text/markdown'})`
exercises the negotiation.

**Every page answers.** One test can hit every address a site publishes: the
parameterless pages from `pagesOf`, the parametric ones from the sitemap
entries:

```dart
test('every page of the site answers 200', () async {
  final app = await TestApp.start(root: const AppModule());
  addTearDown(app.close);
  final client = TestClient.of(app);
  final catalog = app.injector<PageCatalog>();

  final paths = <String>[
    for (final p in catalog.pagesOf<PublicSite>())
      if (!p.path.contains(':'))
        PageMatch(page: p, params: const {}).path,
    await for (final u in catalog.sitemapOf<PublicSite>()) u.location.path,
  ];
  for (final path in paths) {
    expect((await client.head(path)).status, 200, reason: path);
  }
});
```

`sitemapOf` needs a `baseUrl` on the site. To go further and check that the stylesheets, scripts
and images a page links to exist, parse `page.text` with `package:html`
(a `dev_dependency` of your own package; it is not part of the framework)
and request each `href`/`src` the same way.

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
  (`[WARNING] ...`) when no client components are configured. A page that
  uses `Document` without a client script makes Jaspr print this one
  harmless notice at the first render of each process; it cannot be
  silenced. With `JasprConfig(clients:)` holding at least one client component the
  notice does not appear.
- **Read cookies with `GrundScope.of(context).cookies`**, not with Jaspr's
  `context.cookies`, which throws on a malformed `cookie` header.
- **A component that throws** is a 500 `application/problem+json`
  (`PageRenderError`); Jaspr prints the error to stderr. HTML error pages
  come later.
- **Pages are `private, no-cache`** unless a component sets
  `cache-control`: a page may depend on the session.
- **Dotted last segments are file requests** (see
  [Static files](#static-files)).
- **Trailing slash URLs redirect.** With the default `TrailingSlash.never`,
  `/login/` answers `308` to `/login`; set `trailingSlash` on the site to
  change it (see [Addresses](#addresses-base-url-and-trailing-slash)).
- **`<base href="/">`.** Jaspr's `Document` adds `<base href="/">` by
  default, so a link `#section` leads to the home page, not to the
  current one. Write the full `/current/path#section`, or pass
  `Document(base: null)`. A page with [client components](#client-components)
  needs a `<base>` that is absent or `/`, because the bundle's script
  address is relative. The framework does not own the `Document`: your shell
  does.
- **Dotted last segments** (`/projects/v1.2`) are still file requests, but
  a declared alternate suffix (`/projects/grund.md`) and a declared site file
  are matched first; the page of such a value is at `/projects/v1.2/`.
- **A root page and `/:slug`, both with an alternate:** the literal
  `/index.md` (the Markdown of the root page) wins over the alternate of
  `/:slug`, so a page whose slug is `index` links to the root's Markdown.
  Routing is literal first; avoid the slug `index` or give the root page no
  alternate.
- **Sessions live in memory**: they end with the process (a restart under
  `grund dev` signs everyone out) and are not shared between processes.
- **Jaspr is initialized once per process**, without isolates. Calling
  `Jaspr.initializeApp(useIsolates: true)` yourself is a
  `JasprSetupError`, and so are options of your own with client components
  when `JasprConfig.clients` is set (see
  [Client components](#client-components)).
- **`grund_jaspr` does not depend on `grund_auth`**: pages see
  `CurrentUser` only because `SessionHook` sets it in the call scope.
