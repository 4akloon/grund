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
