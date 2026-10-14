# dartnest_build

The build_runner builder of dartnest. It writes `lib/<package>.dartnest.dart`
from the annotations of a package: the same files are read, the same
constructs run and the same bytes are written as by `dartnest_cli gen`.
Use it when a package already generates code with build_runner (for example
`json_serializable`); otherwise `dartnest_cli gen --watch` and `dev` are
faster and need no configuration.

```yaml
# pubspec.yaml
dev_dependencies:
  build_runner: ^2.10.5
  dartnest_build: ^0.1.0-dev
```

```yaml
# build.yaml, next to pubspec.yaml
targets:
  $default:
    builders:
      dartnest_build:
        options:
          package: shop # the name in pubspec.yaml
```

```sh
dart run build_runner build                 # generate once
dart run build_runner watch                 # regenerate on every change
dart run build_runner build --only-check    # build_runner 2.16+: fail if a generated file is out of date, write nothing
```

## The package option

build_runner does not tell a builder which package it builds before the
build, and the builder must declare its output, `lib/<package>.dartnest.dart`,
before. So the package names itself in its `build.yaml`. A missing option,
a name that is not a valid package name, an unknown option or the name of
another package (a `build.yaml` copied from another package) fails the build
with the `build.yaml` to write; nothing is written.

## What it does

- Reads every Dart file of `lib/` except generated `*.dartnest.dart` files
  and runs the core constructs of `dartnest_generator`
  (`DartnestGenerator.core()`), as `dartnest_cli gen` does.
- Problems are build errors, one per line, as
  `path:line:column: error: message [code]`, the lines `dartnest_cli gen`
  prints for the same sources. Syntax errors (in part files too) have the
  code `syntax_error`; the generator's codes are listed in the
  `dartnest_generator` README. Any problem fails the build and nothing is
  written.
- A part another builder has not written yet (`user.g.dart` of
  `json_serializable`) does not change the output: the generator reads
  annotations and declarations, not generated members. `build.yaml` of
  `dartnest_build` has `required_inputs: [".dart"]`, so build_runner runs it
  after the builders that write `.dart` files and types declared in
  generated parts resolve. This is a declaration in `build.yaml`, pinned by
  a test; the order itself is build_runner's. The outputs of builders with
  `build_to: cache` are visible to this builder but not to
  `dartnest_cli gen`, which reads only the files on disk.
- When `lib/` has no annotations, nothing is written; build_runner deletes
  a library it generated before.
- A construct that generates a file of its own (`FileUnit`) fails the
  build: this builder writes only `lib/<package>.dartnest.dart`. Generate
  such a package with `dartnest_cli gen`.

## Differences from dartnest_cli gen

- **The output belongs to build_runner.** `dartnest_cli gen` never
  overwrites a file without the generated header; build_runner deletes a
  file in the way of an output (since build_runner 2.7, conflicting
  outputs are always deleted) before any builder runs. Do not keep a
  hand-written `lib/<package>.dartnest.dart`.
- **Problems delete the library.** `dartnest_cli gen` leaves the library
  as it was while the sources have problems; build_runner deletes the
  previous output of a failed build step, so code that imports the library
  stops compiling until the problems are fixed.
- The generated header is the same, so `dartnest_cli gen` and `dev` accept
  a library build_runner wrote, and the other way round.

## build_runner and dartnest_cli in one package

Both write the same bytes and the same header, so they never fight over
the library, but give it one writer per package:

- `dart run build_runner watch`, when other builders (`json_serializable`)
  run anyway; restart the application yourself.
- `dartnest_cli dev` (or `gen --watch`) for hot reload. If other builders
  need `dart run build_runner watch` beside it, disable `dartnest_build`
  in the package's `build.yaml` (`enabled: false` under
  `dartnest_build:`), so build_runner does not rewrite or delete the
  library `dev` reloads.

## Own constructs

Dart cannot load constructs at run time, so a package with constructs of
its own declares its own builder. With `build`, `dartnest_build` and
`dartnest_generator` in its dev dependencies:

```dart
// tool/builder.dart
import 'package:build/build.dart';
import 'package:dartnest_build/dartnest_build.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

Builder shopBuilder(BuilderOptions options) => DartnestBuildOptions.builderFor(
  options,
  generator: DartnestGenerator([
    ...const DartnestGenerator.core().constructs,
    // MyConstruct(),
  ]),
);
```

```yaml
# build.yaml
builders:
  dartnest:
    import: tool/builder.dart
    builder_factories: [shopBuilder]
    build_extensions: {"$lib$": ["shop.dartnest.dart"]} # <package>.dartnest.dart
    required_inputs: [".dart"] # run after freezed, json_serializable, ...
    build_to: source
    auto_apply: root_package
targets:
  $default:
    builders:
      dartnest_build:
        enabled: false
      shop:dartnest:
        options:
          package: shop
```

## Versions

`build` `^4.0.2`; `analyzer` `>=8.1.1 <15.0.0`, the range of
`dartnest_generator`. With build_runner 2.10.5 to 2.16.2 the builder was
checked on both edges. `--only-check` needs build_runner 2.16, which needs
Dart 3.11; `dartnest_build` itself keeps the SDK floor `^3.8.0`.

The `users_app` fixture depends on `build_runner` `>=2.10.5 <3.0.0`, so the
workspace resolves on every SDK from 3.8 (pub picks 2.16 on Dart 3.11 or
newer; on 3.8 it is expected to pick 2.10, which was not verified here).

## Tests

`dart test` builds packages in memory with `build_test`. The real
build_runner runs only in the integration test, which is not part of
`dart test` (it compiles the build script, about 20 s the first time):

```sh
cd packages/dartnest_build && dart test integration
```

On build_runner older than 2.16 (Dart before 3.11) the integration test
skips itself, because `--only-check` is missing there.

It runs `dart run build_runner build --only-check` in the generator's golden
fixture `users_app` and passes when the committed
`lib/users_app.dartnest.dart` is what the builder writes.
