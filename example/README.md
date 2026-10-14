# tasks_api — the dartnest example

A small tasks API that uses every part of dartnest: modules with imports,
exports and a global module, typed tokens, an interface bound to an
implementation, controllers, a guard chain with route metadata, a pipe, an
interceptor, an exception filter, middleware, both adapters and hot reload.

The same application is wired twice:

- with **annotations** (`lib/src/**`), turned by `dartnest_cli gen` into the
  committed `lib/tasks_api.dartnest.dart`, which exports `appModule`;
- with the **explicit API** by hand in `lib/explicit.dart`, which exports
  `explicitAppModule` and reuses the same classes.

`test/e2e_test.dart` runs one suite against both graphs, each served by
`dart:io` and by shelf on a loopback port.

## Run it

From the repository root, once: `dart pub get`. Then in `example/`:

```sh
dart run bin/main.dart                      # annotations, dart:io, port 8080
dart run bin/main.dart --explicit --shelf   # the explicit graph on shelf
PORT=9090 dart run bin/main.dart
```

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

| Request | Answer |
| --- | --- |
| `GET /health` | `{"status": "ok", "name": "tasks_api"}`, no key needed |
| `/tasks` without `x-api-key`, or an unknown key | 401 |
| `GET /tasks`, `GET /tasks/:id` with `reader-key` or `editor-key` | the tasks; `?done=maybe` or `/tasks/one` is 400, an unknown id 404 |
| `POST`, `PATCH`, `DELETE` with `reader-key` | 403 |
| `POST /tasks` with `editor-key` | 201, `location: /tasks/3`, the title trimmed |
| every response | `x-request-id` (middleware); routed ones also `server-timing` (interceptor) |

## Where each feature is

| Feature | File |
| --- | --- |
| Global module, tokens, `Value` | `lib/src/config/config_module.dart` |
| Module with imports and exports | `lib/src/tasks/tasks_module.dart`, `lib/src/auth/auth_module.dart` |
| Interface bound to an implementation (`Bind`) | `lib/src/tasks/tasks_module.dart` (`TaskStore` → `InMemoryTaskStore`) |
| Injection by type and by token (`@Inject`) | `lib/src/tasks/tasks_service.dart`, `lib/src/auth/api_keys.dart` |
| Controller, routes, parameters, body DTOs | `lib/src/tasks/tasks_controller.dart`, `create_task_dto.dart`, `update_task_dto.dart` |
| Guards and route metadata | `lib/src/auth/api_key_guard.dart`, `roles_guard.dart`, `roles.dart` |
| Pipe | `lib/src/common/trim_strings_pipe.dart` |
| Exception filter | `lib/src/tasks/task_not_found_filter.dart` |
| Application-level interceptor | `lib/src/common/timing_interceptor.dart`, `lib/src/server/tasks_app.dart` |
| Middleware | `lib/src/common/request_id_middleware.dart` |
| Adapter choice | `bin/main.dart` |
| The explicit-API twin | `lib/explicit.dart` |

## Change the annotations

After editing an annotated class, regenerate and commit the library:

```sh
dart run dartnest_cli gen
```

`test/generated_library_test.dart` fails while the committed file is out
of date.

## Hot reload

```sh
dart run dartnest_cli dev                   # or: dart run dartnest_cli dev -- --shelf
```

`dev` generates, starts `bin/main.dart` and watches `lib/` and `bin/`:

- Change the body of `HealthController.check` and save: the next
  `GET /health` answers with the new code, the process id stays and the
  tasks you created are still there (for example `Reloaded 7 libraries
  in 82 ms, 0 routes changed.`; the timing and the library count vary).
- Add a route (`@Get('/live')` on `HealthController`): the library is
  regenerated and reloaded (`1 route changed`).
- Add a field to a class: `dev` restarts the process instead (`Restarting
  bin/main.dart: ... changed a field, a constructor or a top-level
  variable.`) and the in-memory tasks start over.

Press `r` to reload and `R` to restart by hand; Ctrl+C stops.

## Tests

```sh
dart test
```

- `test/e2e_test.dart`: both graphs on both adapters, over loopback.
- `test/in_process_test.dart`: `TestClient`, no server.
- `test/tasks_service_test.dart`: the service alone, and a test module
  with a fake store.
- `test/generated_library_test.dart`: the committed generated library is
  what `dartnest_cli gen` writes.
