# CLAUDE.md

Guidance for working in this repository. Code-quality and process rules are
adapted from the author's `typed_openapi` repository (`CLAUDE.md`,
`CONTRIBUTING.md`); deviations are listed at the bottom.

## Project

`grund` is a NestJS-style modular backend framework for Dart without
`dart:mirrors`: explicit typed core (modules, DI, controllers, request
pipeline), optional annotations turned into that same API by a generator,
pluggable HTTP adapters. It is a Dart pub workspace of pure-Dart packages.

- Specs (binding, the code is the truth where a document lags):
  `docs/superpowers/specs/2026-10-15-grund-core-design.md` (G1: core, HTTP,
  generator), `2026-10-15-grund-generated-output-layout-design.md` (the
  flat `X.g.dart` output) and the platform frame
  `2026-10-15-grund-platform-design.md`.
  `2026-10-13-dartnest-design.md` is the history of the first version.
- Roadmap: `docs/superpowers/ROADMAP.md`. One plan per roadmap stage in
  `docs/superpowers/plans/`; the next plan is written after the previous
  stage ships.
- User documentation: `README.md` and `docs/*.md` (English); the example
  application: `example/` (`tasks_api`, a workspace member, not published;
  the same application in annotations and in the explicit API, with a
  Jaspr site of pages (`example/lib/src/web/`) and a session, tested end to
  end on both adapters); releases:
  `docs/RELEASING.md`.
- Packages (published, versioned independently): `grund` (core: modules, DI, runners,
  logging, no HTTP), `grund_http` (HTTP values, hooks, routing, server
  runner, adapter contract, HTTP annotations), `grund_io` and `grund_shelf`
  (adapters), `grund_generator` (core generator, no HTTP),
  `grund_http_generator` (`@Api` generator), `grund_cli` (`gen`, `dev`,
  `init`), `grund_build` (build_runner builder), `grund_jaspr`
  (server-side rendered Jaspr sites and pages declared as module bindings,
  static files under `/static`, sitemaps), `grund_auth`
  (cookie sessions). Unpublished:
  `grund_conformance` (adapter test suite), the fixture packages
  `cases_app`, `http_cases_app`, `users_app`, and `example`.

Minimum SDK: Dart 3.8 (`^3.8.0`), also for generated code.

The `users_app` fixture (`packages/grund_http_generator/test/fixtures/`) has
the dev dependency `build_runner: '>=2.10.5 <3.0.0'` for the `grund_build`
integration test: pub picks 2.16 on Dart 3.11 or newer and (expected, not
verified here) 2.10 on Dart 3.8, so the workspace is expected to resolve on
the `^3.8.0` floor. The integration test skips itself below build_runner 2.16
(`--only-check` is missing there).

## Commands

`dart` is not always on PATH; with fvm's Flutter it is
`export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`.

```sh
dart pub get                          # repo root, once and after pubspec edits
dart analyze                          # repo root; must print "No issues found!"
cd packages/grund && dart test     # same for every package
dart format packages example          # a second run must change 0 files
cd example && dart test               # the example: e2e on both adapters, golden check
# the example, after changing its annotations (commit the result):
cd example && dart run grund_cli gen
# every published package must print "0 warnings":
cd packages/grund && dart pub publish --dry-run
# packages/grund_http_generator, after a deliberate change of generated output
# (rewrites the committed *.g.dart of the users_app fixture):
GRUND_UPDATE_GOLDENS=1 dart test test/golden
# packages/grund_cli: the generation benchmark (not part of `dart test`):
dart test benchmark
# packages/grund_cli: the dev integration tests (not part of `dart test`):
dart test integration
# packages/grund_build: the real build_runner over the golden fixture
# users_app (not part of `dart test`; about 20 s the first time):
dart test integration
# generate a package with the CLI, e.g. the generator's golden fixture:
dart run grund_cli gen --directory ../grund_http_generator/test/fixtures/users_app
```

Git commands run from the repo root. Commit messages are Conventional Commits
(`feat(core): ...`, `fix(...)`, `refactor(...)`, `docs: ...`, `test(...)`).
`.github/workflows/ci.yaml` is set up to run these: tests on Dart 3.8.0 and
stable; format, analyze (`--fatal-infos`) and the publish dry-run on stable
only. It has not run yet.

## Releases

- The ten published packages are versioned independently: only a
  changed package gets a new version. A constraint between workspace
  members is the lowest version that has what the dependent needs. A release
  is made by pushing the tag `<package>-vX.Y.Z`, which runs
  `.github/workflows/publish.yaml`. Publishing, tags and pushes are done by
  a maintainer by hand, following `docs/RELEASING.md`; no change here
  publishes anything.
- A user-visible change adds a line to the `CHANGELOG.md` of each package
  it touches, under the version it will ship in.
- Each published package has its own `LICENSE` (a copy of the root one) and
  a self-contained `analysis_options.yaml` (pub.dev analyzes a package
  without the repository around it): the root options plus
  `public_member_api_docs`. A change of the root options is repeated there.
- A public member without `///` fails `dart analyze`
  (`public_member_api_docs` in every published package).

## Design rules

- **Nothing is guessed silently.** Every invalid module graph, missing
  provider, bad annotation use or unsupported construct is a typed error or a
  generator diagnostic with a stable code and a `path:line:col`, never a
  silent default or a bare `catch`.
- **Fail fast and before running.** Structural problems surface in
  `ModuleGraph.build` / the generator before any factory runs; no partially
  started container is ever returned.
- **Deterministic generator output.** The same sources and the same
  `dart_style` version give byte-identical generated files: sort everything,
  no hash-ordered iteration when emitting. A change of generated output is a
  breaking change of the generator. The formatter version is part of the
  output contract (the SDK floor is not raised for it), so a golden check of
  a committed file that must pass across `dart_style` releases compares both
  texts after the same `DartFormatter` (`example/test/helpers/
  normalized_source.dart`).
- **The core has no codegen and no server.** `grund` depends only on the
  Dart SDK, `package:meta` and `package:logging`: no `dart:mirrors`, no `dart:io` server, no
  shelf, no analyzer. Annotations are dependency-free libraries of the
  packages they belong to: the DI ones in `package:grund/annotations.dart`
  (a library of their own because `Module` shares its name with the base
  class), the HTTP ones in `package:grund_http/annotations.dart` (the core
  has none of them); the generators recognise them by class name and library
  URI, the HTTP prefix supplied by `ApiConstruct`, and the boundary test
  below is unchanged; `analyzer` is allowed only in `grund_generator`/
  `grund_http_generator`/`grund_cli`/`grund_build`, `vm_service` only in
  `grund_cli`, `build` only in `grund_build`, and `jaspr` only in
  `grund_jaspr` and the example (`grund_auth` does not depend on it, and
  `grund_jaspr` not on `grund_auth`; `grund_jaspr` also uses `logging`, on
  the logger `grund.jaspr`, and `path`). `dart:developer` (SDK) is allowed in the core for
  the hot reload service extensions, which register only outside product
  mode.
- **The core generator knows no HTTP.** `grund_generator` reads modules,
  `@Injectable`, `@Provides` and `Bind` and offers the `Construct`
  contract (annotations, collect into an `ExtensionModel`, claim a
  provider, validate, generate); everything about `@Api`, routes,
  parameters, hooks, validators and bodies lives in
  `grund_http_generator`, which depends on `grund_generator`, never the
  other way round. `packages/grund_generator/test/boundary_test.dart`
  fails when a file of its `lib/` mentions `grund_http`, `HttpApi`,
  `HttpCtx`, `HookRef`, `Route` or an HTTP annotation name.
- **Logging goes through `package:logging`.** The framework logs on named
  loggers `Logger('grund.<area>')` and never configures `Logger.root` itself;
  output is attached explicitly with `LogOutput` (`App.run(log:)`). `App.start`
  and `TestApp` attach nothing. See `docs/logging.md`.
- **Generated code is ordinary code on the public API.** If the generator
  needs something the explicit API cannot express, extend the explicit API
  first.
- **The user's HTTP stack is not ours.** Adapters never rewrite the user's
  server or client setup; `shelfHandler(app)` embeds into an existing shelf
  pipeline unchanged.
- **One output per source library, and the tools own only that.** The
  output of `lib/x.dart` is `lib/x.g.dart` (`GeneratedNames.outputPath`, one
  fixed suffix, because build_runner declares outputs per input): a library
  with the mixins of its `@Module` classes, or a `part of 'x.dart'` with the
  `XRoutes` of its `@Api` classes; a library may not declare both
  (`conflicting_outputs`). A generated file is one whose name ends in
  `.g.dart` and that starts with the header `// GENERATED BY
  grund_generator`. `grund_cli` writes only the files that changed, through a
  temporary file and a rename; never over a file without the header
  (exit 73, so a json_serializable `x.g.dart` is not overwritten); nothing
  at all while the sources have problems; and it deletes a header-carrying
  `*.g.dart` of `lib/` that the new set no longer contains (a file without
  the header is left alone). The watcher recognises generated files by name
  only. Under build_runner (`grund_build`) the output belongs to
  build_runner, which deletes a conflicting file and the output of a failed
  step; the builder writes the same bytes and header as the CLI, so either
  accepts the other's file.
- Escape every string taken from user sources at every interpolation site of
  generated code (`DartString.literal` in `grund_generator`).
- **Annotations share names with the explicit API** (`Module`; `Pattern`
  and `Cookie` also clash with `dart:core` / `dart:io`): a library that
  uses annotations imports `package:grund/annotations.dart` and
  `package:grund_http/annotations.dart` unprefixed, and the explicit API
  prefixed, `package:grund/grund.dart as grund` and
  `package:grund_http/grund_http.dart as http` (the generated code uses
  the same prefixes). A type the host imports with a prefix is not
  resolved in the generated `part` (it shares the host's imports); import
  such a type without a prefix in the library that declares the `@Api`.
- **Hooks are written the short way in annotations**: `use: [ApiKeyHook,
  RolesHook(Role.editor)]` (a type or a const instance); `HookRef` stays
  accepted and is the explicit API's form.

## Code rules

- **Use Dart 3.8 features** (patterns, switch expressions, records, class
  modifiers `final`/`sealed`/`interface`, extension types). Dot shorthands and
  null-aware elements need Dart 3.10 and are not used until the SDK floor is
  raised. Primary constructors are not used.
- **Prefer classes and static members to top-level helper functions** inside
  `lib/src`. Constants live in the class they belong to. Exception: functions
  that the spec defines as public API (dynamic-module factories such as
  `Module databaseModule({...})`, `env(...)`, `describeKey`), builder
  factories that `build.yaml` names (`grundBuilder`, in the
  `grund_build` library) and `main`.
- Lints come from `analysis_options.yaml`; every public member has a `///`
  doc comment; `dart format` keeps the code formatted.
- Tests do not touch the network; HTTP tests use ephemeral ports on
  loopback; temp files only through a `TempDir` test helper.
  `grund_cli` tests build packages in a `TempDir` and resolve them
  against this workspace with `WorkspacePackageConfig` (no `pub get`); they
  run the command line in-process (`CliRun`, `GrundCli(out:, err:,
  interruption:, keys:)`), never as a child process. The exceptions are
  `dev`'s: its tests start the user's application as a child process with
  the VM service on loopback (`AppProcess`, `DevSession`), and
  `integration/` (run with `dart test integration`, not part of `dart
  test`) runs the real `grund dev` as a child process (`dev_test.dart`,
  and `dev_jaspr_test.dart`: a page edit and the live reload event) and
  runs the tests of a fresh `init --template fullstack` package with the
  VM directly against this workspace (`init_fullstack_test.dart`, no `pub
  get`).
  `grund_build` tests build in memory with `build_test`
  (`TestReaderWriter` + `loadIsolateSources()`, no `pub get`), and compare
  with the CLI through `GenerationSession` on a `TempDir` package;
  `integration/build_runner_test.dart` (run with `dart test integration`)
  runs the real build_runner as a child process.

## Code quality rules (size, decomposition, readability)

A reader must understand a unit quickly; if not, decompose it.

| Unit | Limit | Notes |
| --- | --- | --- |
| File in `lib/` | 300 lines | all lines count; use `wc -l` |
| Test file | 500 lines | split by behaviour, helpers to `test/helpers/` |
| Method / function | 40 lines | |
| Parameters | 5 | past that, take a parameter object; `Module` has 6 named fields by spec: it is a declarative value, no parameter object; so are the generator's model classes (`ModuleModel`, `RouteModel`, ...) |
| Nesting | 3 levels of `if`/`for`/`switch`/`try` | early `continue`/`return`, extract |
| Class | one responsibility, ~15 members | not "and" in its one-line doc |
| Declarations per file | one public class or sealed family | small private helpers may share the file |

A flat catalog with no logic may exceed the file limit; note it in the file's
library doc.

**Before you write.** Run `wc -l` on the file you are about to extend. If the
change would take it past the limit, extract first (own commit), then add. A
file already over the limit never grows.

**How to decompose.** Split by responsibility into collaborator classes
(composition), each in its own file. `part`/`part of`, mixins used only to
spread one class over files, and `utils`/`helpers`/`common` files are not
decomposition. A class made public only to leave a file stays out of the
barrel (`lib/grund.dart` uses `show` lists). No hidden state passed through
fields: pass a parameter or a small immutable context object. A refactor
changes no behaviour, keeps tests green and is its own commit. Do not
abstract for a future need: three similar lines beat a premature interface;
an extension point needs a second user first.

**Readability.** Names say what a thing is or does; no abbreviations and no
`2`/`Impl`/`Helper`/`Manager` suffixes. Booleans read as a state in positive
form; no positional `bool` parameters. A comment explains why, never what;
delete a comment that a change made false. Prefer a `switch` over a sealed
type to a chain of `is` tests, and returning a value to mutating an argument.
No `!` where a pattern or early return can promote; no `dynamic`; no `late`
without a comment on why it is set before the first read.

**Dart style (the parts a lint cannot check).** Acronyms longer than two
letters are words (`Http`, `Json`, `Di`); an unused callback parameter is
`_`. Doc comments use `///`, start with a one-sentence summary, refer to
identifiers in `[brackets]`; a boolean starts with "Whether"; no `@param`
tags; do not repeat the signature. No nullable `Future`/`Stream`/collection
returns. No `catch` without `on`; never catch `Error`. The exceptions are
the boundaries where user code runs; each catches `on Object` (except where
the entry names the exact `Error` subtype it catches), has a comment naming
the boundary, and never swallows the failure silently (it wraps, rethrows,
turns it into an error response, or degrades as its entry says while still
producing a response):
- factory and lifecycle boundaries (`grund`): `InjectionRuntime` (provider
  factories) wraps the failure in `ProviderCreationError` with its cause and
  original stack trace; `Container.create` undoes what was created and
  rethrows (a `StartupRollbackError` when the undo failed too);
  `ContainerLifecycle` wraps a failing `onInit` in `ModuleLifecycleError`
  (a `GrundError` passes through); `ShutdownSteps.run` records a failing
  `dispose`/`onShutdown` and goes on with the next step;
- runner boundaries (`grund`): `RunnerSet` wraps a failing runner in
  `RunnerError` (a `GrundError` passes through), rolls back what had been
  started and keeps the previous set serving when a reassemble fails; `App`
  rolls back on a failed start, logs and rethrows a failed reassemble, and
  on `close` waits for a pending reassemble and ignores its failure (that
  goes to the caller of `reassemble`); `HttpServer.start` marks itself
  not listening when the adapter fails and rethrows;
- request boundaries (`grund_http`): `RouteExecutor` (hooks, the handler and
  the serializer run inside it) and `HttpServer` (middleware) turn any
  failure into a problem response through `ProblemResponder`, which logs it
  on `grund.http` and builds the response (`RouteExecutor` then merges the
  headers set so far into it); `HookChain` offers a
  failure to the `onError` hooks in reverse order and rethrows it when none
  answers, and a throwing `onError` replaces the failure the remaining
  hooks see (logged at `FINE`); disposing the call's `Scoped` instances
  after the response was decided reports a `ShutdownError` instead of
  turning it into one;
- exact-type catches in `grund_http` (an `Error` caught by name, never
  `on Object`): `ResponseSerializer` catches `JsonUnsupportedObjectError`
  (an `Error` the JSON encoder throws for a user value) and throws
  `SerializationError` with the original stack trace; `ProblemResponder`
  catches the same error while encoding `details` and falls back to a body
  without them, so the last-resort 500 is always produced; `BodyReader`
  turns a `FormatException` or the `TypeError` of a failed cast in a user
  `fromJson`, and the `FormatException` of a malformed form body (`c.form()`),
  into a 400 (any other failure is a bug and propagates);
  `RequestDispatcher` answers 400 for a malformed percent-encoding of the
  path (`FormatException` of `Uri.pathSegments`);
- the page boundary (`grund_jaspr`): `PagesApi` catches `on
  NotFoundException` around the page builder (nothing else) and answers the
  site's `notFound()` page, inside the site's shell, with status 404; any
  other failure of a builder or component propagates to the request
  boundary (`PageRenderError` for a component that throws);
- the `dev` command boundary (`grund_cli`): `DevCommand` catches `on
  Exception` (not `on Object`: an `Error` is a bug and stays loud) around
  the user's application process, a run and the key actions, and turns the
  failure into a `CliFailure` with the software exit code and a
  `dev stopped:` message, after stopping the process and closing the
  session;
- adapter boundaries: `IoAdapter` reports a failure of the request handler
  (unexpected: the server answers every error itself) to its `onError` and
  answers 500 without a body, and reports a failure while writing the
  response (a failing body stream, a client that went away, a head that
  cannot be written) to its `onError` and drops the connection itself
  (`detachSocket` + `destroy`; it catches the `StateError` dart:io throws
  once the head was sent, because the connection is already dropped then),
  and the adapter keeps serving;
- `ShelfBridge` and `ShelfAdapter` do the same for shelf: `ShelfBridge`
  reports a failure of the request handler to its `onError` and answers 500
  without a body, and reports a failure while discarding the body stream of
  a `HEAD` response (a throwing `onCancel`, a stream already listened to)
  and still answers; `ShelfAdapter` reports a failure of
  `shelf_io.handleRequest` while writing the response to its `onError` and
  drops the connection the same way (same `StateError` catch);
- the reporter boundaries: `IoAdapter` and `GuardedReporter` (shared by
  `ShelfAdapter` and `shelfHandler`) catch a failure of their own `onError`
  and write it to stderr with its stack trace, so reporting never stops the
  500 or the server;
- the hot reload boundary (added by the hot reload work):
  `HotReloadExtension.handle` turns any failure of `reassemble`/`close`
  (user module functions and factories run there) into a
  `ServiceExtensionResponse.error` carrying the error (plus the stack trace
  unless it is a `GrundError`), so `dev` prints it and the application
  keeps serving.
`rethrow` keeps the stack trace. Never silence a lint: no `// ignore:`
without a comment on why, and no rule removed from `analysis_options.yaml`
to make a change pass.

**Tests.** Tests come in the same commit as the code; a new branch of logic
has a test that fails without it. A test names the behaviour, builds its
input in the test or a named helper, and checks one thing. Set-up of more
than about 5 lines repeated becomes a helper. `packages/grund_conformance`
is unpublished test support for the adapter packages: its `lib/` may import
`package:test`, and the `register` methods of its test groups are held to the
test-file limits, not to the 40-line method limit.
The generators' fixture packages (`packages/grund_generator/test/fixtures/*`,
`packages/grund_http_generator/test/fixtures/*`) are unpublished workspace
members; the `*.g.dart` of `users_app` there (`users_module.g.dart`,
`users_api.g.dart`, ...) are the golden files: generated, committed, never
edited by hand (`GRUND_UPDATE_GOLDENS=1` rewrites them after a deliberate
change). The `.g.dart` files of `example/` are generated the same way by
`grund_cli gen`, and a test checks they are up to date.

**Self-review before saying "done".**

1. `wc -l` of every touched file and the longest method added: within limits?
2. Could a new reader say in one sentence what each new class and method is
   for? If not, rename or split.
3. Is there code, a parameter or a flag nothing uses yet? Remove it.
4. `dart analyze` clean, tests green, `dart format packages example`
   changes 0 files, and this file / `docs/` / the package READMEs updated
   if behaviour or structure changed.

## Language

Code, doc comments, diagnostics, READMEs and commit messages are English
(public OSS). The design documents under `docs/superpowers/` (spec, roadmap,
plans) are currently written in Ukrainian; new user-facing documentation is
English.

## Deviations from typed_openapi's rules

- "No top-level functions" is relaxed for spec-mandated public functions.
- Dart 3.10 features (dot shorthands) are off: the floor here is Dart 3.8.
- No `DiagnosticBag` requirement in the core: it reports through typed
  exceptions; the generator reports through diagnostics.
