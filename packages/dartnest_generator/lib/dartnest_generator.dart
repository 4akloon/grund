/// Turns dartnest annotations into ordinary code on the explicit dartnest
/// API, and checks the module graph before the application starts.
///
/// A driver (the CLI, build_runner) resolves the libraries of a package,
/// builds its model with [PackageCollector] and runs a [DartnestGenerator]:
///
/// ```dart
/// final package = PackageCollector('shop', root).collect(libraries);
/// final result = const DartnestGenerator.core().generate(package);
/// if (!result.isSuccess) result.diagnostics.forEach(print);
/// ```
///
/// The model and [Construct] are public so later packages (OpenAPI,
/// GraphQL) can add constructs of their own.
library;

export 'src/collector/package_collector.dart';
export 'src/construct/construct.dart';
export 'src/construct/content_type.dart';
export 'src/construct/dartnest_generator.dart';
export 'src/construct/generated_unit.dart';
export 'src/construct/generation_result.dart';
export 'src/constructs/controller_construct.dart';
export 'src/constructs/module_construct.dart';
export 'src/constructs/provider_construct.dart';
export 'src/diagnostic/diagnostic.dart';
export 'src/diagnostic/diagnostic_code.dart';
export 'src/diagnostic/source_location.dart';
export 'src/diagnostic/syntax_problem.dart';
export 'src/emit/library_writer.dart';
export 'src/model/body_kind.dart';
export 'src/model/component_reference.dart';
export 'src/model/constant_value.dart';
export 'src/model/constructor_model.dart';
export 'src/model/controller_model.dart';
export 'src/model/dependency_model.dart';
export 'src/model/dto_field.dart';
export 'src/model/dto_model.dart';
export 'src/model/enhancers_model.dart';
export 'src/model/generated_names.dart';
export 'src/model/handler_parameter.dart';
export 'src/model/injectable_model.dart';
export 'src/model/module_export.dart';
export 'src/model/module_model.dart';
export 'src/model/module_reference.dart';
export 'src/model/package_model.dart';
export 'src/model/parameter_binding.dart';
export 'src/model/provider_key.dart';
export 'src/model/provider_model.dart';
export 'src/model/route_model.dart';
export 'src/model/type_kind.dart';
export 'src/model/type_model.dart';
