/// Turns grund annotations into ordinary code on the explicit grund
/// API, and checks the module graph before the application starts.
///
/// A driver (the CLI, build_runner) resolves the libraries of a package,
/// builds its model with [PackageCollector] and runs a [GrundGenerator]:
///
/// ```dart
/// final package = PackageCollector('shop', root).collect(libraries);
/// final result = const GrundGenerator.core().generate(package);
/// if (!result.isSuccess) result.diagnostics.forEach(print);
/// ```
///
/// The model and [Construct] are public so later packages (OpenAPI,
/// GraphQL) can add constructs of their own.
library;

export 'src/collector/package_collector.dart';
export 'src/construct/construct.dart';
export 'src/construct/content_type.dart';
export 'src/construct/grund_generator.dart';
export 'src/construct/generated_unit.dart';
export 'src/construct/generation_result.dart';
export 'src/diagnostic/diagnostic.dart';
export 'src/diagnostic/diagnostic_code.dart';
export 'src/diagnostic/source_location.dart';
export 'src/diagnostic/syntax_problem.dart';
export 'src/emit/library_writer.dart';
export 'src/model/api_model.dart';
export 'src/model/binding_key.dart';
export 'src/model/binding_model.dart';
export 'src/model/body_kind.dart';
export 'src/model/constant_value.dart';
export 'src/model/constructor_model.dart';
export 'src/model/dependency_model.dart';
export 'src/model/dto_field.dart';
export 'src/model/dto_model.dart';
export 'src/model/generated_names.dart';
export 'src/model/hook_model.dart';
export 'src/model/injectable_model.dart';
export 'src/model/lifetime.dart';
export 'src/model/module_export.dart';
export 'src/model/module_model.dart';
export 'src/model/module_reference.dart';
export 'src/model/package_model.dart';
export 'src/model/param_location.dart';
export 'src/model/param_model.dart';
export 'src/model/param_source.dart';
export 'src/model/provider_model.dart';
export 'src/model/provides_model.dart';
export 'src/model/return_kind.dart';
export 'src/model/route_model.dart';
export 'src/model/type_kind.dart';
export 'src/model/type_model.dart';
export 'src/model/validator_model.dart';
export 'src/model/value_kind.dart';
