# tasks_api — the grund example

A small tasks API that uses every part of grund: modules with imports,
exports and a global module, a `@Provides` method, an interface bound to an
implementation (`Bind`), `HttpApi` classes with typed path, query and body
readers, `HttpHook`s (by type and by instance, per route, per API and
global), a middleware, both adapters and hot reload.

The same application is wired twice:

- with **annotations** (`lib/src/**`), turned by `grund_cli gen` into the
  committed `*.g.dart` files: the `$Module` mixins and the parts with the
  `HttpApi` classes; the root is `AppModule`;
- with the **explicit API** by hand in `lib/explicit.dart`; the root is
  `ExplicitAppModule`, and it reuses the same services, hooks and handler
  classes. It uses no generated file.

`ServingModule` wraps either root with `HttpModule` and the adapter module
(`IoAdapterModule` or `ShelfAdapterModule`), so the application does not
know how it is served. `test/e2e_test.dart` runs one suite against both
graphs, each served by `dart:io` and by shelf on a loopback port.

## Run it

From the repository root, once: `dart pub get`. Then in `example/`:

```sh
dart run bin/main.dart                      # annotations, dart:io, port 8080
dart run bin/main.dart --explicit --shelf   # the explicit graph on shelf
PORT=9090 dart run bin/main.dart
```

`main` runs `App.run`, which attaches the console log (see
`docs/logging.md`) and closes on Ctrl+C or SIGTERM.

```sh
curl localhost:8080/health
curl -H 'x-api-key: reader-key' localhost:8080/tasks
curl -H 'x-api-key: reader-key' 'localhost:8080/tasks?done=true'
curl -X POST -H 'x-api-key: editor-key' -H 'content-type: application/json' \
  -d '{"title": "  Write the docs  "}' localhost:8080/tasks
curl -X PATCH -H 'x-api-key: editor-key' -H 'content-type: application/json' \
  -d '{"done": true}' localhost:8080/tasks/3
curl -X DELETE -H 'x-api-key: editor-key' localhost:8080/tasks/3
```

Errors are `application/problem+json` (RFC 9457): a `status`, a `detail`, a
stable `code` and, for a bad body, `errors` with a JSON `pointer`.

| Request | Answer |
| --- | --- |
| `GET /health` | `{"status": "ok", "name": "tasks_api"}`, no key needed |
| `/tasks` without `x-api-key`, or an unknown key | 401, `code: api_key_invalid` |
| `GET /tasks`, `GET /tasks/:id` with `reader-key` or `editor-key` | the tasks; `?done=maybe` or `/tasks/one` is 400, an unknown id 404 (`task_not_found`) |
| `POST`, `PATCH`, `DELETE` with `reader-key` | 403, `code: role_required` |
| `POST /tasks` with `editor-key` | 201, `location: /tasks/3`, the title trimmed |
| every response | `x-request-id` (middleware); routed ones also `server-timing` (global hook) |

## Where each feature is

| Feature | File |
| --- | --- |
| Global module, `@Provides` | `lib/src/config/config_module.dart` |
| Module with imports and exports | `lib/src/tasks/tasks_module.dart`, `lib/src/auth/auth_module.dart` |
| Interface bound to an implementation (`Bind`) | `lib/src/tasks/tasks_module.dart` (`TaskStore` to `InMemoryTaskStore`) |
| `@Api`, routes, `@Path`/`@Query`/`@Body` | `lib/src/tasks/tasks_api.dart`, `create_task.dart`, `update_task.dart` |
| Hook by type (resolved from DI) | `lib/src/auth/api_key_hook.dart` (`HookRef<ApiKeyHook>.type()`) |
| Hook by instance, per route | `lib/src/auth/roles_hook.dart`, `lib/src/tasks/location_hook.dart` |
| Hook that turns a domain error into a problem | `lib/src/tasks/task_not_found_hook.dart` |
| Global hook and middleware | `lib/src/common/timing_hook.dart`, `request_id_middleware.dart`, `lib/src/server/serving_module.dart` |
| Adapter choice | `lib/src/server/serving_module.dart`, `bin/main.dart` |
| The generated glue | `lib/src/**/*.g.dart` |
| The explicit-API twin | `lib/explicit.dart` |

## Generated files

Every library with annotations gets one file, `<name>.g.dart`. For a
library with a `@Module` it is the `$Module` mixin (imported by the library
and applied with `with $Module`); for a library with an `@Api` it is a
`part` of it (the library says `part '<name>.g.dart';` and imports
`package:grund_http/grund_http.dart as http`). A library may not declare
both, which is why `health_module.dart` and `health_api.dart` are two
libraries. After editing an annotated class, regenerate and commit:

```sh
dart run grund_cli gen
```

`test/generated_library_test.dart` runs the same generation in a temporary
directory and fails while the committed set differs (a changed, missing or
extra file). Instead of the CLI, `grund_build` generates the same files
under `dart run build_runner build` (add it as a dev dependency next to
`build_runner`); both write identical bytes, so either accepts the other's
output.

## Hot reload

```sh
dart run grund_cli dev                   # or: dart run grund_cli dev -- --shelf
```

`dev` generates, starts `bin/main.dart` and watches `lib/` and `bin/`:

- Change the body of `HealthApi.check` and save: the next `GET /health`
  answers with the new code, the process id stays and the tasks you created
  are still there (`Reloaded 7 libraries in 82 ms, 0 added, 0 removed.`;
  the timing and the library count vary).
- Add a route (`@Get('/live')` on `HealthApi`): the files are regenerated
  and reloaded (`1 added, 0 removed` and the line `+ GET /health/live`).
- Add a field to a class: `dev` restarts the process instead (`Restarting
  bin/main.dart: ... changed a field, a constructor or a top-level
  variable.`) and the in-memory tasks start over.

Press `r` to reload and `R` to restart by hand; Ctrl+C stops.

## Tests

```sh
dart test
```

- `test/e2e_test.dart`: both graphs on both adapters, over loopback.
- `test/in_process_test.dart`: `TestApp` and `TestClient`, no socket.
- `test/tasks_service_test.dart`: the service alone, and a test module
  with a fake store.
- `test/server_options_test.dart`, `test/main_process_test.dart`: the
  command line, a port in use (exit 1) and SIGTERM (exit 0).
- `test/generated_library_test.dart`: the committed generated files are
  what `grund_cli gen` writes.
