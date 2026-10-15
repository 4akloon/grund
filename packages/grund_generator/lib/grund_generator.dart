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
/// The model, [Construct] with its phases and the collector building
/// blocks ([Annotations], [TypeReader], [ConstantReader], ...) are public
/// so other packages can add constructs of their own.
library;

export 'src/collector/annotations.dart';
export 'src/collector/collection_context.dart';
export 'src/collector/constant_reader.dart';
export 'src/collector/entry_read.dart';
export 'src/collector/package_collector.dart';
export 'src/collector/source_locations.dart';
export 'src/collector/type_reader.dart';
export 'src/construct/construct.dart';
export 'src/construct/construct_annotations.dart';
export 'src/construct/content_type.dart';
export 'src/construct/generated_unit.dart';
export 'src/construct/generation_result.dart';
export 'src/construct/grund_generator.dart';
export 'src/construct/provider_claims.dart';
export 'src/constructs/module_construct.dart';
export 'src/diagnostic/diagnostic.dart';
export 'src/diagnostic/diagnostic_code.dart';
export 'src/diagnostic/source_location.dart';
export 'src/diagnostic/syntax_problem.dart';
export 'src/emit/library_writer.dart';
export 'src/model/binding_key.dart';
export 'src/model/binding_lookup.dart';
export 'src/model/binding_model.dart';
export 'src/model/constant_value.dart';
export 'src/model/constructor_model.dart';
export 'src/model/dependency_model.dart';
export 'src/model/extension_model.dart';
export 'src/model/generated_names.dart';
export 'src/model/injectable_model.dart';
export 'src/model/lifetime.dart';
export 'src/model/module_export.dart';
export 'src/model/module_model.dart';
export 'src/model/module_reference.dart';
export 'src/model/package_model.dart';
export 'src/model/provider_model.dart';
export 'src/model/provides_model.dart';
export 'src/model/type_kind.dart';
export 'src/model/type_model.dart';
export 'src/model/unsupported_use.dart';
