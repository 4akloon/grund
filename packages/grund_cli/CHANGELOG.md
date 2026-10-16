## 0.1.2

- `init --template fullstack` scaffolds server-rendered Jaspr pages with
  cookie sessions (`grund_jaspr`, `grund_auth`), a sign-in form, a
  stylesheet in `web/` and tests; `--template api` (the default) is the
  previous scaffold.
- `init --template api` names `grund_http: ^0.2.0` (it named `^0.1.0`).
- `dev` reloads open pages: it serves server-sent events on a loopback
  port, passes the URL in `GRUND_LIVE_RELOAD_URL` and sends `reload` after
  every reload with a successful reassemble and once a started or
  restarted application serves (`grund_jaspr` adds the listening script to
  its pages).

## 0.1.1

- `init` scaffolds a `test/` directory with a smoke test and the `test` dev dependency.

## 0.1.0

Initial release.

- `grund gen` and `gen --watch`: write the generated file set
  (`X.g.dart` per source library) of the module and `@Api` constructs,
  only the files that changed, and nothing while the sources have problems;
  stale generated files are deleted, and a file without the generator's
  header is never overwritten or deleted.
- `grund dev`: runs the application and hot reloads it on every change,
  restarting it when a change of shape needs it; it prints what a reload
  added to and removed from what the application serves (for the HTTP
  server `+ GET /hello/bye`).
- `grund init`: scaffolds a new application (`App`, `@Module`, `@Api`,
  `HttpModule`, `IoAdapterModule`).
- `GrundCli` and `GenerationSession` for tools with constructs of their own.
- A source library with an unresolved `import`, `export` or `part` is a
  problem (`unresolved_uri`): `gen` writes and deletes nothing, exits with 1,
  instead of deleting the generated files.
- `gen` rewrites the generated files once after a change of the resolved
  `dart_style` release; the content is the same.
- A `@Module` in a part file is a `module_in_part` problem instead of an
  unreachable output file.
