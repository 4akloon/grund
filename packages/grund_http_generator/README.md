# grund_http_generator

The HTTP part of the grund generator. `grund_generator` knows modules
and dependency injection only; this package adds `ApiConstruct`, the
`Construct` for `@Api` classes and their routes (`@Get`, `@Post`, ...),
parameters (`@Path`, `@Query`, `@Header`, `@Cookie`, `@Body`), hooks
(`use:`), validators (`@Range`, `@Length`, `@Pattern`, `@OneOf`) and
request and response bodies. The annotations themselves stay in
`grund_annotations`.

An entry of `use:` is a hook class (`ApiKeyHook`, taken from the module
graph), a const hook instance (`RolesHook(Role.editor)`) or a `HookRef`
constant; all three generate the same code.

A driver (the CLI, the build_runner builder) composes the constructs
statically:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';

const constructs = [ModuleConstruct(), ApiConstruct()];

GenerationResult generate(String root, List<LibraryElement> libraries) {
  const generator = GrundGenerator(constructs);
  final package = generator.collector('shop', root).collect(libraries);
  return generator.generate(package);
}
```

`ApiConstruct` collects an `HttpPackageModel` (`package.extensionModel<
HttpPackageModel>()`), claims an `@Api` class listed in a module's
`providers` (binding the class and its `XRoutes`; its hooks bound by type
must be visible in that module), and reports these codes. A package
collected without `ApiConstruct` is a programming error (`StateError`),
never an empty set of apis:

`invalid_api`, `duplicate_api`, `invalid_hook`, `invalid_route_handler`,
`route_outside_api`, `invalid_handler_parameter`,
`parameter_without_source`, `missing_from_json`, `unknown_path_parameter`,
`invalid_validator`, `invalid_status`, `unsupported_return_type`,
`stream_return_reserved`, `duplicate_route`.

The routes are written into the part `X.g.dart` of the library `X.dart`
(`part 'X.g.dart';`), the same name `grund_generator` uses for the module
library of `X.dart`. A library cannot declare both `@Module` and `@Api`: the
core reports `conflicting_outputs` at both declarations, so declare modules
and APIs in separate libraries.
