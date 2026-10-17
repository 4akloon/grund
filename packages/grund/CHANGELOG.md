## 0.2.0

- **Breaking:** requires Dart 3.13 (`sdk: ^3.13.0`).
- `Environment` reads environment variables with checks (`has`, `string`,
  `integer`: a variable that is set must be valid, only an unset one falls
  back), `EnvironmentModule` binds it globally, and `EnvironmentError`
  (`MissingVariableError`, `InvalidVariableError`) never shows a value.

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
- Logging on `package:logging`: `LogOutput` (`console`, `json`, `none`) with
  `ConsoleLogFormatter` and `JsonLogFormatter`, startup, module and shutdown
  messages on `grund.app` / `grund.modules`, and `App.run(log:)`.
- `App.reassemble()` and the `ext.grund.*` VM service extensions that
  `grund_cli dev` uses for hot reload.
- `TestApp` in `package:grund/testing.dart`.
- HTTP lives in `grund_http`.
- The dependency-injection annotations (`@Module`, `@Injectable`, `@Provides`,
  `Bind`, `@Named`, `Scope`) in `package:grund/annotations.dart`, a library of
  their own because `Module` shares its name with the base class.
- `LogSubscription.cancel` is idempotent (a second call no longer restores the
  root level again); the start log says "1 singleton created".
