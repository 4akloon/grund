## 0.1.0

Initial release.

- Modules as classes (`Module`) with imports, `exports`, `qualifier` and
  `global`; explicit typed bindings (`Singleton`, `Scoped`, `Transient`) and a
  graph that is validated before any factory runs: every failure is a typed
  `GrundError` with a hint.
- `Injector`, call scopes (`openCall`, `CallContext`) and `Disposable`.
- `App`, `Runner` and `Runners`: runners are found in the graph, selected with
  `--only`, prepared, started and stopped in order; `close` is idempotent and
  collects every failure in a `ShutdownError`.
- `App.reassemble()` and the `ext.grund.*` VM service extensions that
  `grund_cli dev` uses for hot reload.
- `TestApp` in `package:grund/testing.dart`.
- HTTP lives in `grund_http`.
