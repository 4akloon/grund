## 0.1.0

Initial release.

- `ApiConstruct`: a `Construct` for `grund_generator` that reads `@Api`
  classes, their routes, parameters, hooks, validators and bodies, claims
  an `@Api` class listed in a module's `providers`, and reports their
  problems as diagnostics with a location and a stable code.
- Output: `X_api.g.dart`, a `part of 'X.dart'`, with an `XRoutes extends
  http.HttpApi` per `@Api` class. The library that declares the class must
  include the part and import `package:grund_http/grund_http.dart as http`;
  `missing_part_directive` and `missing_required_import` say what to add.
- `StandardGenerator.instance`: the generator the CLI and the build_runner
  builder run (`ModuleConstruct` and `ApiConstruct`), so both write the
  same files.
