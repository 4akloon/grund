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
  final package = PackageCollector('shop', packageRoot).collect(libraries);
  final result = const GrundGenerator.core().generate(package);
  if (result.isSuccess) {
    // Write result.library to lib/shop.grund.dart.
  } else {
    result.diagnostics.forEach(print);
    // lib/users.dart:12:3: error: No provider for Clock in module "users"
    // (resolving: UsersService). [missing_provider]
  }
}
```

Output (`lib/<package>.grund.dart`, one library per package):

- `@Module class UsersModule` becomes `Module usersModule()`, `@Controller
  class UsersController` becomes `Controller<UsersController>
  usersController()`, plus a private factory per provided class. They are
  functions, not top-level `final`s, so a hot reload rebuilds the graph.
- It imports `package:grund/grund.dart` as `grund` and the user's
  libraries as `i1`, `i2`, ...; it is formatted with `dart_style` for the
  package's language version.
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
| `ModuleConstruct` | `duplicate_module_id`, `circular_module_import`, `duplicate_provider`, `invalid_export`, `invalid_module_entry`, `unsupported_constant`, `missing_provider`, `circular_dependency` |
| `ProviderConstruct` | `not_injectable`, `invalid_constructor`, `invalid_dependency`, `unsupported_constant` |
| `ControllerConstruct` | `invalid_constructor`, `invalid_dependency`, `invalid_component`, `invalid_route_handler`, `invalid_handler_parameter`, `missing_from_json`, `unknown_path_parameter`, `unsupported_constant`, `duplicate_route` (also a controller listed by more than one module) |
| `GrundGenerator` | `duplicate_generated_name` |

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
