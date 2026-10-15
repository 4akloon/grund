import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../model/dependency_model.dart';
import '../model/generated_names.dart';
import '../model/module_export.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/type_model.dart';

/// Checks that the code generated into `X.module.g.dart` can name every
/// class it uses: a private class (`_Foo`) of the module's library is not
/// visible from another library.
abstract final class PrivateDeclarationCheck {
  /// One problem for each private class a module of [package] names.
  static Iterable<Diagnostic> check(PackageModel package) sync* {
    for (final module in package.modules) {
      final output = GeneratedNames.moduleLibraryPath(module.location.path);
      for (final (type, location) in _references(module)) {
        for (final private in _privateTypes(type)) {
          yield Diagnostic(
            DiagnosticCode.privateDeclaration,
            location,
            '$private is private, so the code generated into $output cannot '
            'name it. Make it public.',
          );
        }
      }
    }
  }

  // The types the mixin of [module] writes into generated code.
  static Iterable<(TypeModel, SourceLocation)> _references(
    ModuleModel module,
  ) sync* {
    for (final import in module.imports) {
      yield (import.type, module.location);
    }
    for (final export in module.exports) {
      yield switch (export) {
        KeyExport(:final key) => (key.type, module.location),
        ModuleReexport(:final type) => (type, module.location),
      };
    }
    for (final provider in module.providers) {
      final injectable = provider.injectable;
      yield (provider.key.type, injectable.location);
      yield (injectable.type, injectable.location);
      yield* _dependencies(injectable.constructor.dependencies);
    }
    for (final provided in module.provides) {
      yield (provided.owner, provided.location);
      if (provided.key case final key?) yield (key.type, provided.location);
      yield* _dependencies(provided.dependencies);
    }
  }

  static Iterable<(TypeModel, SourceLocation)> _dependencies(
    List<DependencyModel> dependencies,
  ) sync* {
    for (final dependency in dependencies) {
      if (dependency.key case final key?) {
        yield (key.type, dependency.location);
      }
    }
  }

  static Iterable<TypeModel> _privateTypes(TypeModel type) sync* {
    if (type.name.startsWith('_')) yield type;
    for (final argument in type.typeArguments) {
      yield* _privateTypes(argument);
    }
  }
}
