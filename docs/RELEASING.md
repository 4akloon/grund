# Releasing

How a version of a grund package reaches pub.dev. Tagging and pushing are
done by a maintainer by hand; the tag then runs
`.github/workflows/publish.yaml`, which publishes that one package. No other
change here publishes anything.

## Packages

Ten packages are published. Each has its own version and its own
release: only a package that changed gets a new version and a `CHANGELOG.md`
entry, and a release of package `P` is made by pushing the tag `P-vX.Y.Z`.

| Package | Depends on (published) |
| --- | --- |
| `grund` | none |
| `grund_http` | `grund` |
| `grund_io` | `grund`, `grund_http` |
| `grund_shelf` | `grund`, `grund_http` |
| `grund_auth` | `grund`, `grund_http` (dev: `grund_io`) |
| `grund_jaspr` | `grund`, `grund_http` (dev: `grund_io`) |
| `grund_generator` | none (dev: `grund`, fixture `cases_app`) |
| `grund_http_generator` | `grund_generator` (dev: `grund`, `grund_http`, fixtures `http_cases_app`, `users_app`) |
| `grund_cli` | `grund_generator`, `grund_http_generator` |
| `grund_build` | `grund_generator`, `grund_http_generator` (dev: `grund_cli`) |

The projects that `grund init` scaffolds name published versions of other
packages (`grund_cli` names `grund_jaspr` for the `fullstack` template), so
release the package a scaffold names before the `grund_cli` that names it.

A constraint between workspace members is the lowest version that has what
the dependent needs (`^0.1.0` stays valid when the dependency ships
`0.1.1`; raise it to `^0.1.1` when the dependent needs that fix). The
publish workflow resolves the package's `dependencies` against pub.dev
(`.github/scripts/check_published_dependencies.dart`) and fails before
publishing when a dependency version is not live yet. So when a dependent
raises its constraint to a version of another workspace package that is not
published yet, push the dependency's tag first, wait until its page shows
the version, then push the dependent's tag (or re-run the failed job of the
dependent afterwards). `dev_dependencies` are not checked.

Not published (`publish_to: none`): `grund_conformance` (the adapters'
test suite), the generators' fixture packages `cases_app`, `http_cases_app` and
`users_app`, and the example `tasks_api`. Published packages may list them as dev
dependencies: pub.dev does not require them to exist (checked in the
pub.dev source, `PackageBackend`, on 2026-10-14), pana's checks drop them,
and pub ignores the dev dependencies of a dependency.

## One-time setup of automated publishing

pub.dev publishes from GitHub Actions without a token (OIDC), but only for a
package that already exists on pub.dev. Once per package:

1. **New packages: the first version is published by hand**
   (`cd packages/<package> && dart pub publish`), after the dry-run below.
   Check the name is free first
   (`https://pub.dev/api/packages/<name>` answers 404); a name is taken
   forever once published.
2. On the package's pub.dev admin page (Admin, Automated publishing) enable
   publishing from GitHub Actions: repository `4akloon/grund`, tag pattern
   `<package>-v{{version}}`, and require the GitHub environment `pub.dev`.
3. Once for the repository, on GitHub: create the environment `pub.dev`
   (Settings, Environments) with a required reviewer, and restrict its
   deployment tags to the rule `*-v*`.

## Every release

1. Decide which packages changed since their last tag: a package needs a
   release when its `lib/`, `bin/`, dependencies, README or CHANGELOG
   changed (`git diff --stat <package>-vX.Y.Z..HEAD -- packages/<package>`);
   changes only under `test/` do not.
2. Pick each version (see "Versions" below) and set `version:` in that
   package's `pubspec.yaml`. Raise a constraint on another workspace member
   only when the dependent needs its new version. If the scaffold or a
   README snippet names a version users should depend on
   (`packages/grund_cli/lib/src/init/project_template.dart`, `grundVersion`;
   `fullstack_template.dart`, which also names `grund_http`, `grund_auth`,
   `grund_jaspr` and `jaspr`), keep it resolvable: it must name a version
   that exists.
3. Add a `## x.y.z` section at the top of the `CHANGELOG.md` of each package
   being released. The publish workflow and pub both require it.
4. Run the checks on a clean `master`:

   ```sh
   dart pub get
   dart format --output=none --set-exit-if-changed packages example
   dart analyze --fatal-infos
   for dir in packages/*/ example/; do (cd "$dir" && dart test) || break; done
   (cd packages/grund_cli && dart test integration && dart test benchmark)
   (cd packages/grund_build && dart test integration)
   ```

5. Dry-run every package (not only the ones being released). Each must end
   with `Package has 0 warnings.` and exit with 0 (any warning exits with
   65):

   ```sh
   for package in grund grund_http grund_io grund_shelf grund_auth \
       grund_jaspr grund_generator grund_http_generator grund_cli \
       grund_build; do
     (cd "packages/$package" && dart pub publish --dry-run) || break
   done
   ```

   The dry-run also fails on uncommitted changes: commit first.
6. Commit (`chore: release <package> x.y.z`), push and wait for CI.
7. Tag the commit on `master` and push the tag, one package at a time (for
   several packages, in dependency order, see "Packages"):

   ```sh
   git tag <package>-vX.Y.Z <commit>
   git push origin <package>-vX.Y.Z
   ```

   GitHub starts no tag workflows when more than three tags are pushed at
   once: push tags one at a time or in batches of up to three.

   The workflow checks that the tag matches `pubspec.yaml` and the
   changelog and that the commit is on `master`, then publishes. The
   `pub.dev` environment's reviewer approves the run.

## After publishing

- On each package's pub.dev page: the score (pana) and its suggestions,
  the example tab, the API docs (dartdoc runs on pub.dev) and that the
  `repository` link resolves.
- Dev dependencies on unpublished packages (the fixture packages,
  `grund_conformance`) pass `dart pub publish --dry-run`, but pub.dev
  scoring may fail to resolve them: check the scoring page of a package that
  has them; on a resolution failure drop those dev dependencies from the
  published pubspec in a release commit (the tests that need them stay in
  the repository).
- Outside the repository, with no path overrides:

  ```sh
  dart pub global activate grund_cli
  grund init /tmp/release_check && cd /tmp/release_check
  dart pub get && grund gen && dart run bin/main.dart
  curl 'localhost:8080/hello?name=you'    # {"message":"Hello, you!"}
  ```

- Start the next version: CHANGELOG sections are added when a change is
  made, under the version it will ship in.

## Versions

Each package is versioned on its own. Until 1.0.0, a breaking change raises the minor version (0.1.0 → 0.2.0)
and anything else the patch version. A change of the generator's output
for the same sources is breaking (users' committed generated files
change). Prereleases (`0.2.0-dev.1`) are possible but are not shown to
users by default.
