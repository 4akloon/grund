# build_runner

`grund_build` runs the grund generator as a build_runner builder. For every
library of `lib/` it writes the file `grund gen` writes for it, byte for
byte: `x.g.dart` next to `x.dart` (a library with the `$Module` mixins, or a
`part` with the routes of the `@Api` classes). Use it when the package already
runs build_runner for other builders (`json_serializable`, `freezed`);
otherwise `grund gen` and `grund dev` are faster and need no configuration.

```yaml
# pubspec.yaml
dev_dependencies:
  build_runner: ^2.10.5
  grund_build: ^0.1.0
```

No `build.yaml` is needed: the builder applies to every package that depends
on `grund_build` and has no options.

```sh
dart run build_runner build
dart run build_runner watch
dart run build_runner build --only-check   # build_runner 2.16+: fail if a generated file is out of date, write nothing
```

## How it works

- **One step per library.** The outputs are declared as `.dart` to `.g.dart`,
  one per input, because build_runner needs them before the build. A step
  resolves its library and every library of the same package it reaches
  through imports and exports, generates them as one package and writes the
  files of its own library. A library needs no output when it declares no
  `@Module` or `@Api`.
- **Problems are build errors**, one per line as `grund gen` prints them
  (`path:line:column: error: message [code]`). Each step reports only the
  problems of its own library, so a problem appears once, not once per
  importer.
- **Types from other builders resolve.** The builder runs after the builders
  that write `.dart` files (`required_inputs: [".dart"]`), so a DTO class
  `json_serializable` generates a part for is visible.

## Differences from `grund gen`

- **Problems delete the files of the library.** `gen` keeps the previous
  files while the sources have problems; build_runner deletes the previous
  output of a failed step, so code that imports a generated file stops
  compiling until the problems are fixed.
- **The output belongs to build_runner.** A file in the way of an output is
  deleted before any builder runs; `gen` refuses to overwrite a file without
  the generator header.
- **Reach, not the whole package.** `gen` checks every library together; a
  step checks what its library reaches. The code and the location of a
  problem agree; the text of a hint that names an unreached module can differ.
- **No hot reload.** `build_runner watch` regenerates; restart the
  application yourself.

## json_serializable and freezed

`source_gen`'s combining builder (the `.g.dart` of `json_serializable`)
declares `x.g.dart` for every input, so in a package that uses it too
build_runner stops with `Builders ... outputs collide` for each library both
builders apply to. One `x.g.dart` has one owner. Either keep the classes
`json_serializable` generates for in libraries without `@Module` or `@Api`
(DTOs in their own files, which is also what `grund gen` needs: it never
overwrites a file it did not write), or restrict one of the builders with
`generate_for` in `build.yaml`:

```yaml
targets:
  $default:
    builders:
      grund_build:
        generate_for:
          - lib/**_module.dart
          - lib/**_api.dart
```

The patterns are yours: name the libraries that declare `@Module` or `@Api`,
and keep `json_serializable` classes out of them.

## Using both

They write the same bytes and the same header, so either accepts the other's
output. Give the files one writer at a time:

- `dart run build_runner watch` when other builders run anyway, or
- `grund dev` for hot reload. If `build_runner watch` must run beside it, set
  `enabled: false` under `grund_build:` in `build.yaml`, so the two do not
  both write the files.

Custom constructs need a builder of your own; the
[`grund_build` README](../packages/grund_build/README.md#own-constructs)
shows the `build.yaml`.
