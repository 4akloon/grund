# Dev mode and hot reload

```sh
dartnest dev                          # runs bin/main.dart
dartnest dev -t bin/server.dart -- --port 9090
```

`dev` does what `gen --watch` does and also runs the application. After
every save it regenerates `lib/<package>.dartnest.dart` and then, in the
running process:

1. **hot reloads** the changed libraries (the Dart VM's `reloadSources`);
2. **reassembles** every dartnest application in the process: the module
   functions run again, the new graph is validated, providers that already
   exist keep their instances, new providers are created, removed ones are
   dropped, and controllers and the route table are rebuilt. The swap is
   atomic: a request that is running finishes on the old routes.

The process, its port, its open connections and the state of your
providers survive. One line per event tells you what happened:

```text
# Example output: the timings and the library count vary.
Started bin/main.dart (pid 4242, VM service http://127.0.0.1:40107/abc=/).
Reloaded 7 libraries in 82 ms, 0 routes changed.
Reloaded 7 libraries in 95 ms, 1 route changed.
Restarting bin/main.dart: lib/src/health/health_controller.dart changed a field, a constructor or a top-level variable.
```

## When it restarts instead

A reload keeps existing objects, so it cannot give them a field they were
created without. `dev` therefore restarts the process (the applications
close, requests in flight finish, a new process starts) when a saved file
changed:

- a field, a constructor, a top-level or static variable, or an enum value;
- anything the VM refuses to reload (for example a type parameter).

The restart line names the file. State held in memory starts over.

The check compares declarations as text, file by file, without resolving
types. It errs on the side of restarting: adding a field with an
initializer, which a reload could handle, still restarts.

## While the code has problems

- A problem the generator finds (`missing_provider`, ...) is printed and
  nothing is reloaded: the application keeps running the previous code.
- A compile error outside `lib/` is printed by the reload and changes
  nothing either.
- A reassemble that fails (a factory that throws, an invalid graph) keeps
  the previous modules and routes and prints the error.
- An application that exits or does not start is started again after the
  next change, never in a loop.

## Keys

In a terminal, `r` reloads and `R` restarts (both also start an
application that is not running). Ctrl+C stops `dev` and the application.
In a terminal the application receives the Ctrl+C too and may end before
it closed gracefully; `SIGTERM` sent to `dev` alone closes it first.

## Things to know

- **A reload does not run `main` again.** Changes to the server setup in
  `main` (the adapter, the port, middleware added with `app.use`) take
  effect after `R`.
- **A `Provider.value` keeps its old value**, like every kept instance. A
  changed configuration value needs a restart.
- **Only `lib/` and the directory of the target are watched.** A change in
  a path dependency or in `tool/` is reloaded with `r`, without the restart
  check; press `R` after changing a field there.
- **`pubspec.yaml` is not watched.** Run `dart pub get`, then `R`.
- **If `dev` is killed with `SIGKILL`, the application keeps running**:
  Dart has no parent-death signal. Stop the orphan yourself (its pid is in
  the `Started` line).
- **Only for development.** `dev` runs the application with the VM service
  enabled on loopback. The service extensions `dev` uses
  (`ext.dartnest.reassemble`, `ext.dartnest.close`) are registered only
  outside product mode, so AOT builds (`dart compile exe`) contain none of
  it.

The [`dartnest_cli` README](../packages/dartnest_cli/README.md#dev) has
every rule, timeout and exit code; the [example](../example/README.md#hot-reload)
walks through a session.
