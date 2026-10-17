## 0.2.0

- **Breaking:** requires Dart 3.13 (`sdk: ^3.13.0`).
- A route path of `@Get`, `@Post` and the other route annotations accepts a
  parameter with a literal suffix (`/:slug.md`), as the explicit API does;
  the generated routes need `grund_http` 0.3.0 at runtime.
- `analyzer` is now `>=13.3.0 <15.0.0` (was `>=8.1.1`): the lowest version
  that parses Dart 3.13 sources.

## 0.1.0

Initial release.

- `ApiConstruct`: a `Construct` for `grund_generator` that reads `@Api`
  classes, their routes, parameters, hooks, validators and bodies, claims
  an `@Api` class listed in a module's `providers`, and reports their
  problems as diagnostics with a location and a stable code
  (`HttpDiagnosticCodes`).
- Output: `X.g.dart`, a `part of 'X.dart'`, with an `XRoutes extends
  http.HttpApi` per `@Api` class. The library that declares the class must
  include the part and import `package:grund_http/grund_http.dart as http`;
  `missing_part_directive` and `missing_required_import` say what to add.
  A library cannot declare both `@Module` and `@Api` (`conflicting_outputs`).
- `use:` entries of `@Api` and the route annotations: a hook class, a const
  instance of a hook or a `HookRef` constant, all generated as the same
  `http.HookRef<T>.type()` / `.instance(...)`. Anything else is reported as
  `invalid_hook`, naming the entry and the three accepted forms; an entry
  that cannot be written into generated code (a private hook class, say) is
  `unsupported_constant`.
- `StandardGenerator.instance`: the generator the CLI and the build_runner
  builder run (`ModuleConstruct` and `ApiConstruct`), so both write the
  same files.
- Known limitation: a type the host library imports with a prefix is not
  resolved in the generated part.
