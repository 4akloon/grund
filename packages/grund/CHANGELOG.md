## 0.1.0

Initial release.

- Modules as values, typed providers (`Provider`, `Provider.value`,
  `Provider.async`, tokens) and a container that validates the module graph
  before any provider is created; every failure is a typed `InjectionError`.
- Controllers and routes as values; the request pipeline (middleware,
  guards, interceptors, pipes, exception filters) with `Enhancers` and
  `Use<T>()`; JSON results and `HttpException` error responses.
- `HttpAdapter`, the contract the server adapters implement, and
  `TestClient` for tests without a socket.
- `Application.reassemble()` and the `ext.grund.*` VM service extensions
  that `grund_cli dev` uses for hot reload.
