# FAQ and known limitations

## FAQ

**Do I have to use annotations?**
No. The explicit API is the framework; annotations are a shorter way to
write it. Applications, tests and libraries work without any code
generation, and the two styles can be mixed in one graph.

**Why one generated file per package instead of `part` files?**
Your files stay untouched, the output is one reviewable diff, and the
generator can validate the whole module graph at once.

**Should I commit the generated library?**
Yes. It is ordinary Dart that changes only when the annotations do, and
committing it means `dart run` works right after `dart pub get`. Check it
in CI with `dartnest gen && git diff --exit-code`.

**Does it work with AOT (`dart compile exe`)?**
Yes. Nothing uses `dart:mirrors`. The hot reload hooks are registered only
outside product mode, so an AOT binary contains none of them.

**Can I use Flutter's `dart:ui` or run in the browser?**
`package:dartnest` itself does not import `dart:io`, but both adapters do,
and the framework is built and tested as a server framework only.

**How do I override a provider in a test?**
There is no `overrideProvider`; build a test module with the providers you
want. See [testing.md](testing.md#a-test-module).

**Where are lifecycle hooks (`OnModuleInit`, `OnApplicationShutdown`)?**
Not in 0.1.0. An async provider's factory is the place for startup work;
for shutdown, close your resources after `await app.close()`.

**Is there OpenAPI support?**
Not yet. The generator already collects what an OpenAPI document needs
(types, doc comments, DTOs); a `dartnest_openapi` package is the next
planned milestone.

**Which Dart versions are supported?**
The packages declare `sdk: ^3.8.0` and use no language feature newer than
Dart 3.8. Development and the tests ran on Dart 3.13. The CI workflow is
set up to test 3.8.0 and stable, but it has never run, so the 3.8 floor is
unverified.

## Not in 0.1.0

Request-scoped providers, lifecycle hooks, WebSockets and server-sent
events, GraphQL, microservice transports, OpenAPI generation, a `relic`
adapter, and code scaffolding beyond `dartnest init` (no `nest g`).

## Known limitations

These are known and deliberate trade-offs or open problems of 0.1.0.

**An unresolved annotation import deletes the generated library.**
`dartnest gen` keeps the previous library while the sources have problems
it can report: syntax errors and its own diagnostics. An analyzer error
that hides the annotations is not such a problem. If the import of
`package:dartnest_annotations` is broken in every annotated file (a typo,
a missing dependency), the generator sees no annotations and deletes
`lib/<package>.dartnest.dart` in that run, exiting with 0
(`No annotations in lib/; deleted lib/my_app.dartnest.dart.`). Fix the
import and run `gen` again; the file comes back unchanged. Under `dev` the
reload that follows fails to compile and the application keeps running the
previous code; the next save after the fix regenerates and reloads.

**`dev` may restart when a reload would have been enough.** The check
that decides between a reload and a restart compares fields,
constructors, top-level and static variables and enum values as text,
without resolving types. Any change there restarts the process, also when
a reload could have handled it (a new field with an initializer, a
reformatted constructor). The reverse does not happen for files `dev`
watches; for files it does not watch (path dependencies, `tool/`), press
`R` after changing a field.

**The generator cannot see into a module from another package.** A
`@Module` class from another package, and a module returned by a
function, are opaque to the generator. For the whole package that
references one, `missing_provider` and `circular_dependency` are not
reported by `dartnest gen`; `Application.create` still reports them at
startup, with the resolution chain.

**`HeaderMap` does not validate header values.** The core accepts CR and
LF in a header value. With both bundled adapters such a value never
reaches the wire: `dart:io` refuses it when the response is written, the
client's connection is closed without a response, and the error goes to
the adapter's `onError`. A custom adapter must validate values itself.
Do not copy unchecked user input into response headers.

**build_runner deletes the library on problems.** With `dartnest_build`,
a failed build step deletes the previous `lib/<package>.dartnest.dart`, so
code that imports it stops compiling until the problems are fixed.
`dartnest gen` keeps the previous file instead. See
[build-runner.md](build-runner.md).

**A hot reload does not run `main` again.** Changes to the server setup in
`main` need a restart (`R`). A `Provider.value` keeps its old value across
reloads.

**Killing `dev` with `SIGKILL` leaves the application running.** Dart has
no parent-death signal. Stop the orphan process yourself; its pid is in
the `Started` line.

**A Dart default value of a `@Query` parameter is ignored.** A
non-nullable `@Query('limit') int limit = 20` is still required (a
request without it gets a 400). Declare `int? limit` and write
`limit ?? 20` in the method.

**No request body size limit.** Handlers read the body as a stream and
decide how much to accept; `bodyAs` reads all of it. Put a limit in a
proxy or a middleware if clients are untrusted.

**Platforms.** Development and every test run on Linux. macOS is expected
to work like Linux but is not tested. Windows is not verified: path
handling in the CLI is written for it, but `dev` (signals, the terminal
keys, process restarts) has never run there.

**The SDK floor is declared, not yet tested.** The packages declare Dart
3.8; the local runs used Dart 3.13. The CI workflow tests 3.8.0, but it
has not run yet.
