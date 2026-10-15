## 0.1.0

Initial release.

- `grund gen` and `gen --watch`: write the generated file set
  (`X.g.dart` per source library) of the module and `@Api` constructs,
  only the files that changed, and delete stale generated files; a file
  without the generator's header is never overwritten or deleted. A
  `lib/<package>.grund.dart` written by an earlier version is not touched:
  delete it by hand.
- `grund dev`: runs the application and hot reloads it on every change,
  restarting it when a change of shape needs it; it prints what a reload
  added to and removed from what the application serves (for the HTTP
  server `+ GET /hello/bye`).
- `grund init`: scaffolds a new application (`App`, `@Module`, `@Api`,
  `HttpModule`, `IoAdapterModule`).
