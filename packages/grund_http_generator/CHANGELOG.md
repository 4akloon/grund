## 0.1.0

Initial release.

- `ApiConstruct`: a `Construct` for `grund_generator` that reads `@Api`
  classes, their routes, parameters, hooks, validators and bodies, claims
  an `@Api` class listed in a module's `providers`, and reports their
  problems as diagnostics with a location and a stable code.
