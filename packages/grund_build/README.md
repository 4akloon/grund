# grund_build

The build_runner builder of grund. For every Dart library of `lib/` it
writes the file `grund_cli gen` writes for it: `x.g.dart` next to `x.dart`,
a library with the mixins of its modules when `x.dart` declares `@Module`,
or the part of `x.dart` with the routes when it declares `@Api`. A library
may not declare both (`conflicting_outputs`): put modules and APIs in
separate libraries. The same constructs run and the same
bytes and header are written as by `grund_cli gen`.
Use it when a package already generates code with build_runner (for example
`json_serializable`); otherwise `grund_cli gen --watch` and `dev` are
faster and need no configuration.

```yaml
# pubspec.yaml
dev_dependencies:
  build_runner: ^2.16.0
  grund_build: ^0.1.0
```

No `build.yaml` is needed: the builder applies to every package that
depends on `grund_build` and has no options.

```sh
dart run build_runner build                 # generate once
dart run build_runner watch                 # regenerate on every change
dart run build_runner build --only-check    # build_runner 2.16+: fail if a generated file is out of date, write nothing
```

## What it does

One build step runs per library of `lib/`; the outputs are declared as
`.dart` to `.g.dart` (one output per input, as build_runner needs it), and a
step writes it only when its library needs it (build_runner accepts an
output that is not written).

- **What a step reads.** The module graph and dependency checks need the
  modules a library reaches, so the step resolves its library and every
  library of the same package it reaches through imports and exports,
  collects and generates them as one package, and writes the files of its
  own library. Other packages are not followed. A library that nothing
  reaches from the input does not influence the input's files.
- **Problems are build errors, one per line,** as
  `path:line:column: error: message [code]`, the lines `grund_cli gen`
  prints. Only the problems of the step's own library (and its part files)
  are reported by that step; a problem in an imported library is reported by
  the step of that library, so it appears once, not once per importer.
  Syntax errors have the code `syntax_error`; the generator's codes are
  listed in the `grund_generator` and `grund_http_generator` READMEs. While a
  library it reaches has a problem, a step writes nothing; if its own library
  is fine it logs `<path> was not generated: <libraries> have problems`, so a
  missing file always has a message, even when that library is not a build
  input.
- Generated files (name `*.g.dart` and the generator's header) and part
  files are not inputs.
- **`X.g.dart` has one owner.** build_runner checks declared outputs, not
  written ones: `source_gen`'s combining builder (the `.g.dart` of
  `json_serializable`) declares `x.g.dart` for every input, so in a package
  that uses it too, build_runner stops with `Builders ... outputs collide`
  for each library both builders are applied to. Restrict one of them with
  `generate_for` in your `build.yaml` (for example grund_build to the
  libraries with `@Module` or `@Api`, and these libraries then hold no
  `json_serializable` classes), or generate with `grund_cli gen`, which
  never overwrites a file it did not write.
- A part another builder has not written yet (`user.g.dart` of
  `json_serializable`, in a library grund_build is not applied to)
  does not change the output: the generator reads
  annotations and declarations, not generated members. `build.yaml` of
  `grund_build` has `required_inputs: [".dart"]`, so build_runner runs it
  after the builders that write `.dart` files and types declared in
  generated parts resolve. This is a declaration in `build.yaml`, pinned by
  a test; the order itself is build_runner's.
- The files of one build step are invisible to the analyzer of that step:
  `x.dart` imports `x.g.dart`, which the step is about to write. The
  generator does not need its content.

## Differences from grund_cli gen

- **The output belongs to build_runner.** `grund_cli gen` never
  overwrites a file without the generated header; build_runner deletes a
  file in the way of an output before any builder runs, and deletes the
  output of a library that no longer needs it (`grund_cli gen` deletes only
  stale files that have the header).
- **Problems delete the files of the library.** `grund_cli gen` leaves the
  files as they were while the sources have problems; build_runner deletes
  the previous output of a failed build step, so code that imports a
  generated file stops compiling until the problems are fixed.
- **Reach, not the whole package.** `grund_cli gen` checks every library of
  the package together; a step checks what its library reaches. A check
  that only sees the whole package (a hint that names an unreached module in a
  message, for example) can differ in text; the code and location agree.
  A library no other library reaches is checked by its own step only, so
  a syntax error in an unrelated library does not stop the others'
  files from being written, though the build fails.
- The generated header is the same, so `grund_cli gen` and `dev` accept
  files build_runner wrote, and the other way round.

## build_runner and grund_cli in one package

Both write the same bytes and the same header, so they never fight over
the files, but give them one writer per package:

- `dart run build_runner watch`, when other builders (`json_serializable`)
  run anyway; restart the application yourself.
- `grund_cli dev` (or `gen --watch`) for hot reload. If other builders
  need `dart run build_runner watch` beside it, disable `grund_build`
  in the package's `build.yaml` (`enabled: false` under
  `grund_build:`), so build_runner does not rewrite or delete the
  files `dev` reloads.

## Own constructs

Dart cannot load constructs at run time, so a package with constructs of
its own declares its own builder. With `build`, `grund_build`,
`grund_generator` and `grund_http_generator` in its dev dependencies:

```dart
// tool/builder.dart
import 'package:build/build.dart';
import 'package:grund_build/grund_build.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';

Builder shopBuilder(BuilderOptions options) => GrundBuilder(
  generator: GrundGenerator([
    ...StandardGenerator.instance.constructs,
    // MyConstruct(),
  ]),
);
```

```yaml
# build.yaml
builders:
  grund:
    import: tool/builder.dart
    builder_factories: [shopBuilder]
    build_extensions: {".dart": [".g.dart"]}
    required_inputs: [".dart"] # run after freezed, json_serializable, ...
    build_to: source
    auto_apply: root_package
targets:
  $default:
    builders:
      grund_build:
        enabled: false
```

The builder writes only a module library and an API part per library; a file
of another kind that a construct generates (a `FileUnit`) fails the build:
`grund_build cannot write <path>` (every step that reaches it says so).
Generate such a package with `grund_cli gen`.

## Versions

`build` `^4.0.2`; `analyzer` `>=13.3.0 <15.0.0`, the range of
`grund_generator`. The `users_app` fixture depends on `build_runner`
`^2.16.0` (Dart 3.11 or newer, which the SDK floor `^3.13.0` satisfies), the
version whose `build --only-check` the integration test runs.

## Tests

`dart test` builds packages in memory with `build_test`. The real
build_runner runs only in the integration test, which is not part of
`dart test` (it compiles the build script, about 20 s the first time):

```sh
cd packages/grund_build && dart test integration
```

It runs `dart run build_runner build --only-check` in the golden fixture
`users_app` of `grund_http_generator` and passes when its committed
`*.g.dart` files are what the builder writes.
