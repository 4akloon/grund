# CLAUDE.md

Guidance for working in this repository. Code-quality and process rules are
adapted from the author's `typed_openapi` repository (`CLAUDE.md`,
`CONTRIBUTING.md`); deviations are listed at the bottom.

## Project

`dartnest` is a NestJS-style modular backend framework for Dart without
`dart:mirrors`: explicit typed core (modules, DI, controllers, request
pipeline), optional annotations turned into that same API by a generator,
pluggable HTTP adapters. It is a Dart pub workspace of pure-Dart packages.

- Spec: `docs/superpowers/specs/2026-10-13-dartnest-design.md` (binding).
- Roadmap: `docs/superpowers/ROADMAP.md`. One plan per roadmap stage in
  `docs/superpowers/plans/`; the next plan is written after the previous
  stage ships.

Minimum SDK: Dart 3.8 (`^3.8.0`), also for generated code.

The `users_app` fixture has the dev dependency `build_runner: '>=2.10.5 <3.0.0'`
for the `dartnest_build` integration test: pub picks 2.16 on Dart 3.11 or newer
and (expected, not verified here) 2.10 on Dart 3.8, so the workspace resolves
on the `^3.8.0` floor. The integration test skips itself below build_runner
2.16 (`--only-check` is missing there).

## Commands

`dart` is not always on PATH; with fvm's Flutter it is
`export PATH="$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH"`.

```sh
dart pub get                          # repo root, once and after pubspec edits
dart analyze                          # repo root; must print "No issues found!"
cd packages/dartnest && dart test     # same for every package
dart format packages                  # a second run must change 0 files
# packages/dartnest_generator, after a deliberate change of generated output:
DARTNEST_UPDATE_GOLDENS=1 dart test test/golden
# packages/dartnest_cli: the generation benchmark (not part of `dart test`):
dart test benchmark
# packages/dartnest_cli: the dev integration tests (not part of `dart test`):
dart test integration
# packages/dartnest_build: the real build_runner over the golden fixture
# users_app (not part of `dart test`; about 20 s the first time):
dart test integration
# generate a package with the CLI, e.g. the generator's golden fixture:
dart run dartnest_cli gen --directory ../dartnest_generator/test/fixtures/users_app
```

Git commands run from the repo root. Commit messages are Conventional Commits
(`feat(core): ...`, `fix(...)`, `refactor(...)`, `docs: ...`, `test(...)`).

## Design rules

- **Nothing is guessed silently.** Every invalid module graph, missing
  provider, bad annotation use or unsupported construct is a typed error or a
  generator diagnostic with a stable code and a `path:line:col`, never a
  silent default or a bare `catch`.
- **Fail fast and before running.** Structural problems surface in
  `ModuleGraph.build` / the generator before any factory runs; no partially
  started container is ever returned.
- **Deterministic generator output.** The same sources give byte-identical
  generated files: sort everything, no hash-ordered iteration when emitting.
  A change of generated output is a breaking change of the generator.
- **The core has no codegen and no server.** `dartnest` depends only on the
  Dart SDK and `package:meta`: no `dart:mirrors`, no `dart:io` server, no
  shelf, no analyzer. Annotations live in their own dependency-free package;
  `analyzer` is allowed only in `dartnest_generator`/`dartnest_cli`/
  `dartnest_build`, `vm_service` only in `dartnest_cli`, and `build` only
  in `dartnest_build`. `dart:developer` (SDK) is allowed in the core for
  the hot reload service extensions, which register only outside product
  mode.
- **Generated code is ordinary code on the public API.** If the generator
  needs something the explicit API cannot express, extend the explicit API
  first.
- **The user's HTTP stack is not ours.** Adapters never rewrite the user's
  server or client setup; `shelfHandler(app)` embeds into an existing shelf
  pipeline unchanged.
- **The CLI owns only its output.** `dartnest_cli` writes
  `lib/<package>.dartnest.dart` only when it changed, through a temporary
  file and a rename, never over a file without the generated header, and
  leaves it as it was while the sources have problems. Under build_runner
  (`dartnest_build`) the output belongs to build_runner, which deletes a
  conflicting file and the output of a failed step; the builder writes the
  same bytes and header as the CLI, so either accepts the other's file.
- Escape every string taken from user sources at every interpolation site of
  generated code (`DartString.literal` in `dartnest_generator`).
- **Annotations share names with the explicit API** (`Module`,
  `Controller`): a library that uses both imports
  `package:dartnest/dartnest.dart` with `hide Controller, Module`, and a
  module written with the explicit API lives in a file without that `hide`.

## Code rules

- **Use Dart 3.8 features** (patterns, switch expressions, records, class
  modifiers `final`/`sealed`/`interface`, extension types). Dot shorthands and
  null-aware elements need Dart 3.10 and are not used until the SDK floor is
  raised. Primary constructors are not used.
- **Prefer classes and static members to top-level helper functions** inside
  `lib/src`. Constants live in the class they belong to. Exception: functions
  that the spec defines as public API (dynamic-module factories such as
  `Module databaseModule({...})`, `env(...)`, `describeKey`), builder
  factories that `build.yaml` names (`dartnestBuilder`, in the
  `dartnest_build` library) and `main`.
- Lints come from `analysis_options.yaml`; every public member has a `///`
  doc comment; `dart format` keeps the code formatted.
- Tests do not touch the network; HTTP tests use ephemeral ports on
  loopback; temp files only through a `TempDir` test helper.
  `dartnest_cli` tests build packages in a `TempDir` and resolve them
  against this workspace with `WorkspacePackageConfig` (no `pub get`); they
  run the command line in-process (`CliRun`, `DartnestCli(out:, err:,
  interruption:, keys:)`), never as a child process. The exceptions are
  `dev`'s: its tests start the user's application as a child process with
  the VM service on loopback (`AppProcess`, `DevSession`), and
  `integration/dev_test.dart` (run with `dart test integration`, not part
  of `dart test`) also runs the real `dartnest dev` as a child process.
  `dartnest_build` tests build in memory with `build_test`
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
barrel (`lib/dartnest.dart` uses `show` lists). No hidden state passed through
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
- factory boundaries: `ModuleInjector` (provider factories) and
  `Controller.instantiate` wrap the failure in `ProviderCreationError` /
  `ControllerCreationError` with its cause and original stack trace;
- request boundaries (added by the HTTP pipeline work): `Pipeline.run` hands
  the failure to the exception filters and rethrows it when none handles it;
  `RequestDispatcher.dispatch` and `Application.handle` turn it into a 500
  through `HttpErrorResponder`, which logs it;
- `ResponseSerializer` (added by the HTTP pipeline work) catches
  `JsonUnsupportedObjectError` (an `Error` the JSON encoder throws for a user
  value) and throws `SerializationError` with the original stack trace;
- `HttpErrorResponder` (added by the HTTP pipeline work) catches the exact
  `JsonUnsupportedObjectError` while encoding `details` and falls back to a
  body without them, so the last-resort 500 is always produced;
- adapter boundaries (added by the adapters work): `IoAdapter` reports a
  failure of the request handler (only possible when the application's own
  error logger throws) to its `onError` and answers 500 without a body, and
  reports a failure while writing the response (a failing body stream, a
  client that went away, a head that cannot be written) to its `onError` and
  drops the connection itself (`detachSocket` + `destroy`; dart:io only
  drops it once the head was sent), and the adapter keeps serving;
- `ShelfBridge` and `ShelfAdapter` (added by the adapters work) do the same
  for shelf: `ShelfBridge` reports a failure of the request handler to its
  `onError` and answers 500 without a body, and reports a failure while
  discarding the body stream of a `HEAD` response (a throwing `onCancel`, a
  stream already listened to) and still answers; `ShelfAdapter` reports a failure
  of `shelf_io.handleRequest` while writing the response to its `onError`
  and drops the connection the same way;
- the reporter boundaries (added by the adapters work): `IoAdapter` and
  `GuardedReporter` (shared by `ShelfAdapter` and `shelfHandler`) catch a
  failure of their own `onError` and write it to stderr with its stack
  trace, so reporting never
  stops the 500 or the server;
- the hot reload boundary (added by the hot reload work):
  `HotReloadExtension.handle` turns any failure of `reassemble`/`close`
  (user module functions and factories run there) into a
  `ServiceExtensionResponse.error` carrying the error (plus the stack trace
  unless it is a `DartnestError`), so `dev` prints it and the application
  keeps serving.
`rethrow` keeps the stack trace. Never silence a lint: no `// ignore:`
without a comment on why, and no rule removed from `analysis_options.yaml`
to make a change pass.

**Tests.** Tests come in the same commit as the code; a new branch of logic
has a test that fails without it. A test names the behaviour, builds its
input in the test or a named helper, and checks one thing. Set-up of more
than about 5 lines repeated becomes a helper. `packages/dartnest_conformance`
is unpublished test support for the adapter packages: its `lib/` may import
`package:test`, and the `register` methods of its test groups are held to the
test-file limits, not to the 40-line method limit.
The generator's fixture packages (`packages/dartnest_generator/test/fixtures/*`)
are unpublished workspace members; `users_app.dartnest.dart` there is the
golden file: generated, committed, never edited by hand.

**Self-review before saying "done".**

1. `wc -l` of every touched file and the longest method added: within limits?
2. Could a new reader say in one sentence what each new class and method is
   for? If not, rename or split.
3. Is there code, a parameter or a flag nothing uses yet? Remove it.
4. `dart analyze` clean, tests green, `dart format packages` changes 0
   files, and this file / `docs/` updated if behaviour or structure changed.

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
