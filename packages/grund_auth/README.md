# grund_auth

Cookie sessions for grund applications: an opaque session token in an
`HttpOnly` cookie, a global hook that puts the `CurrentUser` of a request in
its call scope, and a same-origin check for unsafe requests.

```dart
final class AccountApi extends HttpApi {
  AccountApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.get('/me', (c) => {'user': c.maybe<CurrentUser>()?.id}),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name', minLength: 1);
    // Check a password or another credential here before signing in.
    await _sessions.start(c, name);
    return HttpResponse.redirect(Uri.parse('/me'), status: StatusCode.seeOther);
  }
}

final class AppModule extends Module {
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SessionHook>.type()]),
    IoAdapterModule(),
    // Plain http here; keep the default `secure: true` behind HTTPS.
    SessionModule(config: SessionConfig(secure: false)),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AccountApi>(
      (i) => AccountApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}
```

This package checks no credentials: the application verifies a password,
a one-time code or anything else, then calls `Sessions.start`.

## Sessions

- `SessionModule` is global and binds `SessionConfig`, `SessionStore`
  (`InMemorySessionStore` unless `store:` creates another), `Sessions` and
  `SessionHook`. Register the hook once, globally:
  `HttpModule(use: [HookRef<SessionHook>.type()])`.
- `Sessions.start(c, userId)` deletes the session the request came with,
  creates a new one under a fresh token and sets its cookie. A token known
  before the sign-in never becomes valid, so a planted cookie cannot fix
  the session. It also puts the `CurrentUser` in the call scope of the
  request.
- `Sessions.end(c)` deletes the session and sends the cookie empty with
  `Max-Age=0`. `Sessions.current(c)` is the live session or `null`.
- `SessionHook` puts `CurrentUser(userId)` in the call scope of a request
  with a live session: `c.maybe<CurrentUser>()` in a handler or hook,
  `context.maybe<CurrentUser>()` in a `grund_jaspr` page. No cookie, a
  value that is not a token, an unknown or an expired session is not an
  error: the request simply has no `CurrentUser`.
- A token is 32 bytes of `Random.secure()`, base64url without padding (43
  characters). The cookie carries only the token; nothing is signed and
  there are no keys. A session lasts `SessionConfig.maxAge` (7 days) from
  the sign-in and is not extended by use.
- `InMemorySessionStore` loses its sessions when the process ends and is
  not shared between processes. Implement `SessionStore` (`create`, `read`,
  `delete`) for a durable one. It sweeps expired sessions on every
  `create` (O(n)), and with a sign-in that needs no credentials (as in the
  example) unauthenticated requests can create sessions that live for
  `maxAge`: use a real credential check, rate limiting and a persistent or
  bounded store in production.

## The cookie

In production use `SessionConfig(cookieName: '__Host-grund_sid', secure:
true)`: the `__Host-` prefix defeats cookie tossing from a sibling
subdomain (with duplicate cookies the first one wins).

`SessionConfig` names the cookie (`grund_sid`) and sets `secure` (on by
default), `maxAge`, `sameSite` (`Lax`) and `sameOrigin`. The cookie is
always `HttpOnly` with `Path=/` and no `Domain`:

```text
set-cookie: grund_sid=<token>; Max-Age=604800; Path=/; Secure; HttpOnly; SameSite=Lax
```

The configuration is checked when the application starts and throws a
`SessionConfigError` before the server serves: a name that is not a cookie
token, a `maxAge` under one second, `SameSite=None` without `Secure`, or a
`__Host-`/`__Secure-` name without `Secure`. Turn `secure` off only for
development over plain `http`.

`SetCookie` writes any other cookie the same checked way:
`c.response.headers.add('set-cookie', SetCookie('theme', 'dark').toHeader())`.
A name that is not a token, a value with a space, quote, comma, semicolon,
backslash or control character, a path that is empty, does not start with
`/` or has a `;`, a negative `maxAge`, a positive `maxAge` under one second
(it would truncate to `Max-Age=0` and delete the cookie) or
`SameSite=None` without `Secure` throws a `CookieFormatError`, so a value
taken from a request cannot add attributes or headers. `SetCookie` does not
enforce a prefix policy: a hand-built `__Host-` cookie is not checked for
`Secure` or `Path=/` (`SessionConfig` checks the prefix rules for its own
cookie). Several `set-cookie` headers (the session's and the handler's own)
all reach the client.

## Cross-site requests

With `SessionConfig.sameOrigin` (the default) `SessionHook` refuses an
unsafe request (not `GET`, `HEAD` or `OPTIONS`) that a browser sent from
another site with a 403 `cross_site_request`: one whose `sec-fetch-site`
is neither `same-origin` nor `none`, or whose `origin` does not name the
`host` it was sent to. A request without these headers (curl, another
server) passes. `SameOriginHook` is the same check for an application
without sessions. Together with `SameSite=Lax` it replaces CSRF tokens for
browsers that send these headers; behind a proxy that rewrites `host`,
forward the original one. More than one `origin` header is refused, and
only the host and port of `origin` are compared, not its scheme.

Not in this release: passwords, OAuth, JWT, CSRF tokens, roles, durable
stores.
