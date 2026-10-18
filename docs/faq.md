# FAQ and known limitations

## FAQ

**Do I have to use annotations?**
No. The explicit API is the framework; annotations are a shorter way to
write it. Applications, tests and libraries work without any code
generation, and the two styles mix in one graph: a generated module can
import a hand-written one and the other way round.

**Can grund serve HTML pages?**
Yes, server-side rendered with Jaspr in the same process as the API:
`grund_jaspr` serves the sites, pages, static files and sitemaps,
`grund_auth` adds a cookie session that pages and handlers share.
Interactivity comes from server-rendered HTML fragments swapped in by htmx
(`Fragments.respond`), or from hydrated Jaspr components registered in
`JasprConfig(clients:)` and compiled by `grund bundle`; there is no
`@client` annotation yet. See [jaspr.md](jaspr.md).

**Where is the controller, the guard, the pipe, the interceptor, the filter?**
An `HttpApi` (`@Api`) is the controller. One type, `HttpHook`, replaces the
rest: `before` is a guard (throw to refuse), `before` and `after` together are
an interceptor, `onError` is an exception filter. Pipes are the `Params`
readers (`c.query.integer('limit', min: 1)`) or `@Range`, `@Length`,
`@Pattern` and `@OneOf`. See [http-and-hooks.md](http-and-hooks.md).

**Why `as grund` and `as http`?**
The annotation `Module` and the base class `Module` have the same name, and
`Pattern` and `Cookie` clash with `dart:core` and `dart:io`, so the
annotations are libraries of their own (`package:grund/annotations.dart`,
`package:grund_http/annotations.dart`) imported unprefixed, and the explicit
API is imported with a prefix: `grund.Module` is what you extend, `http.HttpApi`
is what the generated routes extend. See
[annotations-and-codegen.md](annotations-and-codegen.md#the-annotations).

**Why is there no `<package>.grund.dart`?**
There used to be one library per package. The generator now writes one file
per source library, next to it: `x.g.dart` for `x.dart` (the `$Module` mixins,
or the `part` with the routes of its `@Api` classes). Delete a leftover
`lib/<package>.grund.dart`; `grund gen` removes only generated files it
recognises (a `.g.dart` name and the generator header), so it is yours to
delete.

**Can I use json_serializable or freezed?**
Yes, for the DTOs. They write `x.g.dart` too, and one `x.g.dart` has one
owner: keep those classes in libraries without `@Module` or `@Api`, or
restrict `grund_build` with `generate_for`. `grund gen` never overwrites a
file it did not write; build_runner reports an output conflict. See
[build-runner.md](build-runner.md#json_serializable-and-freezed).

**My log listener throws. What happens?**
The response of the request is still produced, but the failure is not
contained: `package:logging` delivers records through a stream, so the error
goes to the zone the listener was registered in. In a plain `main` without
`runZonedGuarded` it is an uncaught asynchronous error that ends the
isolate, and with it the server. Keep listeners from throwing (wrap the
code of an error tracker in `try/catch`) or run the application inside
`runZonedGuarded` with the listener registered inside that zone (a
`LogOutput` given to `App.run(log:)` already is; your own
`Logger.root.onRecord.listen` must be called in the guarded callback, not
before it). See [logging.md](logging.md#errors).

**Should I commit the generated files?**
Yes. They are ordinary Dart that changes only when the annotations do, and
committing them means `dart run` works right after `dart pub get`. Check them
in CI with `grund gen && git diff --exit-code`.

**Does it work with AOT (`dart compile exe`)?**
Yes. Nothing uses `dart:mirrors`. The hot reload hooks are registered only
outside product mode, so an AOT binary contains none of them.

**Can I use Flutter's `dart:ui` or run in the browser?**
Not supported. `package:grund` imports `dart:io` for the console log output
and the stop signals, the adapters for the server, and the framework is built
and tested as a server framework only.

**How do I override a provider in a test?**
`TestApp.start(root: ..., overrides: [...])` replaces bindings by key, or build
a test module with the providers you want. See [testing.md](testing.md).

**Where are lifecycle hooks?**
`Module.onInit(injector)` runs once the graph exists, `onShutdown(injector)`
at close; a singleton that implements `Disposable` is disposed when the
application closes. An async binding's factory is the place for startup work.

**Is there OpenAPI support?**
Not yet. The generator already collects what an OpenAPI document needs
(types, doc comments, DTOs); a `grund_openapi` package is the next planned
milestone.

**Which Dart versions are supported?**
The packages declare `sdk: ^3.13.0`. Development and the tests ran on Dart
3.13. The CI workflow is set up to test 3.13.0 and stable, but it has never
run.

## Not in 0.1.0

WebSockets and server-sent events, GraphQL, microservice transports, OpenAPI
generation, a `relic` adapter, and code scaffolding beyond `grund init` (no
`nest g`). Request-scoped values exist as call scopes (`Scoped` bindings,
`c.set`), not as NestJS's request-scoped providers.

## Known limitations

These are known and deliberate trade-offs or open problems of 0.1.0.

**What happens with a broken import in a source library?** An `import`,
`export` or `part` of a source library that does not resolve (a typo in
`package:grund/annotations.dart`, a missing dependency) is reported by
`grund gen` and by the build_runner step as `unresolved_uri`, at the
directive, and no generated file is written or
deleted until you fix it. The one exception is a not yet generated
file of your own package with a double extension such as `x.g.dart`
(relative, or `package:<your package>/...`): a library that imports or
includes its own output must keep working on a fresh checkout. The same name
in another package (`package:grund/annotations.g.dart`) is a typo and a
problem. Under `dev`, problems keep the application running the previous
code.

**A type imported with a prefix is not resolved in an `@Api` part.** The
generated `x.g.dart` is a `part` of the host library and shares its imports,
so a type the host imports as `import 'x.dart' as x;` cannot be named in the
routes. Import the type without a prefix in the library that declares the
`@Api` class (the `as http` import is the one prefix the generator needs).

**The generator cannot see into a module from another package.** A `@Module`
class from another package, `HttpModule` and the adapter modules included, and
a module that a function returns are opaque to the generator. While a package
imports one, a dependency that no module of the package binds is not
reported as `missing_provider` by `grund gen`, because the opaque module might export it. A key that a module
of the package binds but does not export to the module that needs it is
still reported, and cycles and captive dependencies among the package's own
bindings are still found. The application start validates the whole graph
before it serves and reports what the generator could not, with the
resolution chain.

**`dev` may restart when a reload would have been enough.** The check that
decides between a reload and a restart compares fields, constructors,
top-level and static variables, enum values and the headers of classes and
similar declarations as text, without resolving types. Adding, removing or
renaming such a declaration in an existing file counts as a change too. Any
change there restarts the process, also when a reload could have
handled it (a new field with an initializer, a reformatted constructor). The
reverse does not happen for files `dev` watches; for files it does not watch
(path dependencies, `tool/`), press `R` after changing a field.

**`HeaderMap` does not validate header values.** The core accepts CR and LF in
a header value. With both bundled adapters such a value never reaches the
wire: `dart:io` refuses it when the response is written, the client's
connection is closed without a response, and the error goes to the adapter's
`onError`. A custom adapter must validate values itself. Do not copy
unchecked user input into response headers.

**build_runner deletes the files on problems.** With `grund_build`, a failed
build step deletes the previous output of its library, so code that imports
it stops compiling until the problems are fixed. `grund gen` keeps the
previous files instead. See [build-runner.md](build-runner.md).

**A hot reload does not run `main` again.** Changes to the server setup in
`main` need a restart (`R`). A kept singleton keeps its old state across
reloads.

**Killing `dev` with `SIGKILL` leaves the application running.** Dart has no
parent-death signal. Stop the orphan process yourself; its pid is in the
`Started` line.

**Request bodies are limited, not streamed through the readers.**
`HttpConfig.maxBodyBytes` (1 MiB by default) bounds `c.body`, `c.bodyList`
and `c.bytes`; a larger body is a 413. A handler that reads
`c.request.body` as a stream decides for itself how much to accept.

**A log listener that throws can end the process.** See the FAQ above and
[logging.md](logging.md#errors).

**Platforms.** Development and every test run on Linux. macOS is expected to
work like Linux but is not tested. Windows is not verified: path handling in
the CLI is written for it, but `dev` (signals, the terminal keys, process
restarts) has never run there.

**The SDK floor is declared, not yet tested.** The packages declare Dart 3.13;
the local runs used Dart 3.13.5. The CI workflow tests 3.13.0, but it has not
run yet.
