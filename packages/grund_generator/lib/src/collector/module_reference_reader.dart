import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/generated_names.dart';
import '../model/module_reference.dart';
import 'annotations.dart';
import 'type_reader.dart';

/// Reads a module reference in `imports` or `exports` of `@Module`: a
/// `@Module` class, or a tear-off of a function without required
/// parameters that returns a core `Module`.
final class ModuleReferenceReader {
  /// Creates the reader for package [packageName].
  ModuleReferenceReader(this.packageName);

  /// The package being generated.
  final String packageName;

  /// The reference [entry] denotes, or `null` when it is not a module.
  ModuleReference? read(DartObject entry) {
    if (entry.toTypeValue() case final InterfaceType type) {
      return _class(type);
    }
    if (entry.toFunctionValue() case final function?) {
      return _function(function);
    }
    return null;
  }

  /// Whether [type] is a `@Module` class.
  static bool isModuleClass(DartType type) =>
      type is InterfaceType && Annotations.find(type.element, 'Module') != null;

  ModuleReference? _class(InterfaceType type) {
    if (!isModuleClass(type)) return null;
    final uri = type.element.library.uri;
    if (uri.scheme != 'package' || uri.pathSegments.isEmpty) return null;
    final owner = uri.pathSegments.first;
    if (owner == packageName) {
      return LocalModuleReference(TypeReader.read(type));
    }
    return OpaqueModuleReference(
      name: GeneratedNames.module(type.element.displayName),
      libraryUri: GeneratedNames.library(owner),
    );
  }

  ModuleReference? _function(ExecutableElement function) {
    final name = function.name;
    final library = function.library;
    final enclosing = function.enclosingElement;
    final ok =
        name != null &&
        !function.formalParameters.any((p) => p.isRequired) &&
        TypeReader.isGrund(function.returnType, 'Module') &&
        function.isPublic &&
        (function is TopLevelFunctionElement ||
            (function is MethodElement &&
                function.isStatic &&
                enclosing is InterfaceElement &&
                enclosing.isPublic));
    if (!ok) return null;
    return OpaqueModuleReference(
      name: name,
      libraryUri: '${library.uri}',
      enclosingName: enclosing is InterfaceElement ? enclosing.name : null,
    );
  }
}
