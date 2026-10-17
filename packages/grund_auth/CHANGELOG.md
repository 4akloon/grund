## 0.2.0

- **Breaking:** requires Dart 3.13 (`sdk: ^3.13.0`).

## 0.1.0

Initial release.

- `SessionModule`, `SessionConfig`, `Sessions` (`start`, `end`,
  `current`): cookie sessions with an opaque random token, a new token on
  every sign-in (no session fixation) and an absolute lifetime.
- `SessionHook`: puts the `CurrentUser` of a live session in the call
  scope and, with `SessionConfig.sameOrigin`, refuses unsafe cross-site
  requests; `SameOriginHook` is that check alone.
- `SessionStore` and `InMemorySessionStore`.
- `SetCookie`, `CookieAttributes` and `SameSitePolicy`: `set-cookie`
  values checked against RFC 6265 (`CookieFormatError`); an invalid
  `SessionConfig` is a `SessionConfigError` at startup.
