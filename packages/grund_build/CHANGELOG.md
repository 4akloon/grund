## 0.2.0

- **Breaking:** requires Dart 3.13 (`sdk: ^3.13.0`).
- `analyzer` is now `>=13.3.0 <15.0.0` (was `>=8.1.1`): the lowest version that parses Dart 3.13 sources.

## 0.1.0

Initial release.

- The `grund_build` builder for build_runner: one build step per library of
  `lib/`, writing `x.g.dart` (the mixins of the modules, or the part with the
  routes of `@Api` classes), the same files and bytes as
  `grund_cli gen`. Each step checks the library it reaches through imports
  and exports and reports only the problems of its own library. No
  `build.yaml` options: the builder applies to every package that depends
  on `grund_build`.
- A library with an unresolved `import`, `export` or `part` fails its own
  step with `unresolved_uri`, as `grund_cli gen` reports it.
- A `@Module` in a part file fails the step of its library with
  `module_in_part`, as the CLI reports it.
