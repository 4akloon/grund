# Releasing

How a version of the dartnest packages reaches pub.dev. Every step that
leaves this machine (creating the GitHub repository, pushing, publishing,
tagging) is done by a maintainer by hand; nothing in this repository runs
it automatically.

## Packages and order

Seven packages are published, always together and with the same version
(lockstep): a release bumps all of them, even a package without changes, so
`^0.1.0` constraints between them never mix versions.

| Order | Package | Depends on (published) |
| --- | --- | --- |
| 1 | `dartnest_annotations` | none |
| 2 | `dartnest` | none |
| 3 | `dartnest_io` | `dartnest` |
| 4 | `dartnest_shelf` | `dartnest` |
| 5 | `dartnest_generator` | none (dev: `dartnest`, `dartnest_annotations`) |
| 6 | `dartnest_cli` | `dartnest_generator` |
| 7 | `dartnest_build` | `dartnest_generator` |

pub.dev rejects an upload whose `dependencies` are not on pub.dev yet, so
publish in this order. It does not check `dev_dependencies`.

Not published (`publish_to: none`): `dartnest_conformance` (the adapters'
test suite), the generator's fixture packages `cases_app` and `users_app`,
and the example `tasks_api`. Published packages may list them as dev
dependencies: pub.dev does not require them to exist (checked in the
pub.dev source, `PackageBackend`, on 2026-10-14), pana's checks drop them,
and pub ignores the dev dependencies of a dependency.

## Before the first release

1. **The name.** The packages are named `dartnest*`. On 2026-10-14 none of
   the seven names was taken on pub.dev
   (`https://pub.dev/api/packages/<name>` answered 404). Check again right
   before publishing; a name is taken forever once published. To rename,
   replace `dartnest` in every pubspec, import, README and doc
   (`git grep -l dartnest`), then run every check below.
2. **The repository.** Every pubspec points to
   `https://github.com/4akLoon/dartnest` (branch `master`). Create that
   repository and push `master`, or replace the URL everywhere:
   `git grep -l 'github.com/4akLoon/dartnest'`.
3. **CI.** Push, and wait for `.github/workflows/ci.yaml` to pass on both
   SDKs (3.8.0 and stable). Until it has run once, the SDK floor 3.8 is
   declared but not verified.
4. **The publisher (optional).** A verified publisher (a domain you own)
   shows on pub.dev instead of a personal account. It can be added after
   the first upload with `dart pub` and the pub.dev admin page.

## Every release

1. Pick the version (see "Versions" below) and set it in all seven
   `pubspec.yaml` files and in every `^x.y.z` constraint between them,
   including `example/`, `packages/dartnest_conformance` and the generator
   fixtures. `packages/dartnest_cli/lib/src/init/project_template.dart`
   (`dartnestVersion`) and the `^0.1.0` snippets in the READMEs and `docs/`
   name the version users should depend on: update them too.
2. Add a `## x.y.z` section at the top of each package's `CHANGELOG.md`.
   pub warns when the changelog does not mention the version being
   published. A package without changes gets "No changes; released with
   the other dartnest packages."
3. Run the checks on a clean `master`:

   ```sh
   dart pub get
   dart format --output=none --set-exit-if-changed packages example
   dart analyze --fatal-infos
   for dir in packages/*/ example/; do (cd "$dir" && dart test) || break; done
   (cd packages/dartnest_cli && dart test integration && dart test benchmark)
   (cd packages/dartnest_build && dart test integration)
   ```

4. Dry-run every package, in the order above. Each must end with
   `Package has 0 warnings.` and exit with 0 (any warning exits with 65):

   ```sh
   for package in dartnest_annotations dartnest dartnest_io dartnest_shelf \
       dartnest_generator dartnest_cli dartnest_build; do
     (cd "packages/$package" && dart pub publish --dry-run) || break
   done
   ```

   The dry-run also fails on uncommitted changes: commit first.
5. Commit (`chore: release x.y.z`) and push; wait for CI.
6. Publish, in the same order, one package at a time:

   ```sh
   cd packages/dartnest_annotations && dart pub publish
   ```

   `dart pub publish` asks for confirmation and, the first time, for a
   Google login in the browser. Wait until each package's page shows the
   new version before publishing the next one.
7. Tag the commit, one tag per package, and push the tags:

   ```sh
   for package in dartnest_annotations dartnest dartnest_io dartnest_shelf \
       dartnest_generator dartnest_cli dartnest_build; do
     git tag "$package-vx.y.z"
   done
   git push origin --tags
   ```

## After publishing

- On each package's pub.dev page: the score (pana) and its suggestions,
  the example tab, the API docs (dartdoc runs on pub.dev) and that the
  `repository` link resolves.
- Outside the repository, with no path overrides:

  ```sh
  dart pub global activate dartnest_cli
  dartnest init /tmp/release_check && cd /tmp/release_check
  dart pub get && dartnest gen && dart run bin/main.dart
  curl 'localhost:8080/hello?name=you'    # {"message":"Hello, you!"}
  ```

- Start the next version: CHANGELOG sections are added when a change is
  made, under the version it will ship in.

## Versions

Until 1.0.0, a breaking change raises the minor version (0.1.0 → 0.2.0)
and anything else the patch version. A change of the generator's output
for the same sources is breaking (users' committed generated files
change). Prereleases (`0.2.0-dev.1`) are possible but are not shown to
users by default; the lockstep rule applies to them too.

## Automated publishing (later)

pub.dev can publish from GitHub Actions when a tag is pushed, without a
token: enable "Automated publishing" on each package's admin page (tag
pattern `<package>-v{{version}}`), then add a workflow with
`dart-lang/setup-dart/.github/workflows/publish.yml`. The first version of
each package must still be published by hand.
