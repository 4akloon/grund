# grund_http_generator

The HTTP part of the grund generator. `grund_generator` knows modules
and dependency injection only; this package adds `ApiConstruct`, the
`Construct` for `@Api` classes and their routes (`@Get`, `@Post`, ...),
parameters (`@Path`, `@Query`, `@Header`, `@Cookie`, `@Body`), hooks
(`use:`), validators (`@Range`, `@Length`, `@Pattern`, `@OneOf`) and
request and response bodies. The annotations themselves stay in
`grund_annotations`.

A driver (the CLI, the build_runner builder) composes the constructs
statically:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';

const constructs = [ModuleConstruct(), ApiConstruct()];

GenerationResult generate(String root, List<LibraryElement> libraries) {
  final package = PackageCollector(
    'shop',
    root,
    constructs: constructs,
  ).collect(libraries);
  return const GrundGenerator(constructs).generate(package);
}
```

`ApiConstruct` collects an `HttpPackageModel` (`package.extensionModel<
HttpPackageModel>()`), claims an `@Api` class listed in a module's
`providers` (its hooks bound by type must be visible in that module), and
reports these codes:

`invalid_api`, `duplicate_api`, `invalid_hook`, `invalid_route_handler`,
`route_outside_api`, `invalid_handler_parameter`,
`parameter_without_source`, `missing_from_json`, `unknown_path_parameter`,
`invalid_validator`, `invalid_status`, `unsupported_return_type`,
`stream_return_reserved`, `duplicate_route`.
