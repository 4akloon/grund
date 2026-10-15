# grund_generator

Turns `grund_annotations` into ordinary code on the explicit grund
API and checks the module graph before the application starts. This
package is the library the drivers (a command line tool, a build_runner
builder) run; it does not read or write files itself.

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';

void generate(String packageRoot, List<LibraryElement> libraries) {
  // libraries: the resolved libraries of the package's lib/.
  const generator = GrundGenerator.core();
  final package = generator.collector('shop', packageRoot).collect(libraries);
  final result = generator.generate(package);
  if (result.isSuccess) {
    // Write each entry of result.files (path -> content) under packageRoot.
  } else {
    result.diagnostics.forEach(print);
    // lib/users.dart:12:3: error: No provider for Clock in module "users"
    // (resolving: UsersService). [missing_provider]
  }
}
```

Output, one file per source library (`result.files`, path to content):

- The output of a source library `lib/users.dart` is always
  `lib/users.g.dart`, one fixed suffix (`GeneratedNames.outputPath`):
  build_runner declares its outputs per input, so the name cannot depend on
  what the library declares. What the file is follows from its content, and
  one library cannot need two kinds: units of a library and of a part for
  one path are a `conflicting_outputs` diagnostic at both declarations
  (declare modules and APIs in separate libraries). A name owned by another
  tool (`json_serializable`, `freezed`) is not guessed around: the CLI
  refuses to write over a file without the generator header, build_runner
  reports its own conflict.
- A library with `@Module` classes gets that file as a library: for each module `UsersModule` a
  `mixin $UsersModule on grund.Module` with the `imports`, `bindings`,
  `exports` and `global` overrides. The module class applies it with
  `with $UsersModule`. A library without a module gets no file.
- A provider a construct claims is written as the `emission` expression of
  its binding, in the place of the provider.
- Every file imports `package:grund/grund.dart` as `grund` and the user's
  libraries as `i1`, `i2`, ... (numbered within the file); it is formatted
  with `dart_style` for the package's language version.
- The same sources give byte-identical output, whatever the order of the
  libraries; a change of output is a breaking change of the generator.
- `PackageModel` lists modules, injectables and controllers in library-URI
  order, then source order within a library, and DTOs sorted by library URI,
  then class name. This is the order `PackageCollector` produces, and the
  generated declarations follow it. A custom `Construct` or a hand-built
  model must keep that order to get stable output.

Annotation details that are easy to miss:

- A non-nullable `@Query` parameter with a Dart default value is still
  required: a request without it gets a 400, the Dart default is never
  used. Make the parameter nullable to make it optional and apply the
  default in the handler body.
- `Module` and `Controller` are also names of the explicit API; see
  `grund_annotations` for the `hide` rule.

Diagnostics stop generation; each has a stable code:

| Construct | Codes |
| --- | --- |
| `ModuleConstruct` | `circular_module_import`, `duplicate_binding`, `invalid_export`, `invalid_module_entry`, `invalid_module_class`, `invalid_name`, `missing_provider`, `circular_dependency`, `captive_dependency`, `not_injectable`, `invalid_constructor`, `invalid_dependency`, `invalid_provides`, `invalid_scope`, `invalid_bind`, `unsupported_constant`, `unsupported_use`, `private_declaration` |
| `GrundGenerator` | `duplicate_generated_name`, `conflicting_outputs`, `conflicting_provider_claim` |

`unsupported_constant` is reported wherever a constant must be written into
generated code: a `@Module` entry such as `Value(...)` or a token
(`ModuleConstruct`), an `@Inject(token)` of a provider constructor
(`ProviderConstruct`), and an `@Inject(token)` of a controller constructor
or route metadata (`ControllerConstruct`).

`missing_provider` and `circular_dependency` need the whole graph: when a
module is built by a function or comes from another package, the generator
cannot see its providers and skips these two checks for the whole package,
leaving them to `Application.create`.

`Construct` and the model (`PackageModel`, `ModuleModel`, `RouteModel`,
`DtoModel`, ...) are public, so other packages can add constructs.

`analyzer` is accepted from 8.1.1 to 14.x, so the generator runs on Dart
3.8 and on current SDKs.
