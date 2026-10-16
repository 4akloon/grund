# Pages and sessions: Jaspr and grund_auth

One grund process can serve the JSON API and HTML pages rendered on the
server by [Jaspr](https://pub.dev/packages/jaspr), with one dependency
injection, one lifecycle and one cookie session:

- [`grund_jaspr`](../packages/grund_jaspr) renders pages: `JasprModule`
  serves `GET /` and `GET /*` below the API routes, and components read the
  call scope of their request (`context.call<T>()`).
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

```dart
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

final class HomePage extends StatelessComponent {
  const HomePage();

  @override
  Component build(BuildContext context) {
    final user = context.maybe<CurrentUser>();
    final tasks = context.call<TasksService>().list();
    return Document(
      title: 'Tasks',
      body: div([
        p([Component.text(user == null ? 'Signed out.' : 'Hi ${user.id}.')]),
        ul([for (final task in tasks) li([Component.text(task.title)])]),
      ]),
    );
  }
}
```

`context.call<T>()`, `context.maybe<T>()` and `context.injector` have the
semantics of `HttpCtx`: the bindings visible to `JasprModule` (the exports
of its `imports:` and of global modules) and what hooks `set` for this
request. `Component.text` escapes its text, so a user name cannot inject
markup.

`package:jaspr/server.dart` and `package:grund/grund.dart` both declare
`Key`. A file that imports both hides Jaspr's:
`import 'package:jaspr/server.dart' hide Key;`. A page file that imports
only `grund_jaspr` and `grund_auth` needs nothing hidden.

## The module

```dart
final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SessionHook>.type()]),
    IoAdapterModule(),
    SessionModule(config: SessionConfig(secure: false)), // dev over http
    JasprModule(app: Site.new, imports: [TasksModule()]),
  ];
}
```

- `JasprModule` does not import `HttpModule`; the application imports it
  once, and its hooks and middleware run for pages too.
- `app` builds the root component for **every request**. Route between
  pages inside it, with `context.url` or `jaspr_router`.
- API routes win: a literal or `:param` segment beats the pages' `*`, so
  `/tasks/1` is the API's and `/about` is a page. `GET /` belongs to the
  pages: an API route `GET /` is a `DuplicateRouteError` at startup.
- `JasprModule(app:)` takes a function, which an annotation cannot hold:
  write the module that imports it with the explicit API. It can sit next
  to annotated modules (the example's `WebModule` does).

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

Cross-site form posts are refused: `SessionHook` answers an unsafe request
whose `sec-fetch-site` is another site, or whose `origin` is not the
`host` (more than one `origin` header is refused; the scheme is not
compared), with a 403 `cross_site_request`. The
[`grund_auth` README](../packages/grund_auth/README.md) has every rule.

## Static files

`web/` next to `pubspec.yaml` is served before pages: `web/styles.css` is
`GET /styles.css`. Run the application from the package root (`grund dev`
does). Paths with dot segments, separators or links out of the directory
are never files. `JasprConfig(staticDirectory:)` names another directory.

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
session back with `headers: {'cookie': ...}`.

## Hot reload

`grund dev` serves pages like any route: an edited component shows in the
next response, without a restart (the process id stays), because `app` is
called for every request. A new route of an `HttpApi` is picked up by the
reassemble; a new field restarts the process, as everywhere in
[dev mode](dev-mode.md).

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
- **Sessions live in memory**: they end with the process (a restart under
  `grund dev` signs everyone out) and are not shared between processes.
- **Jaspr is initialized once per process**, without isolates. Calling
  `Jaspr.initializeApp(useIsolates: true)` yourself is a
  `JasprSetupError`.
