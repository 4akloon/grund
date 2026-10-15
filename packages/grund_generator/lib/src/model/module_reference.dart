import 'type_model.dart';

/// A module listed in `@Module(imports: ...)` or re-exported.
sealed class ModuleReference {
  /// Creates the reference.
  const ModuleReference();

  /// The reference as written in the annotation, for messages.
  String get display;
}

/// A class annotated with `@Module` in the generated package.
final class LocalModuleReference extends ModuleReference {
  /// Creates the reference.
  const LocalModuleReference(this.type);

  /// The module class.
  final TypeModel type;

  @override
  String get display => type.display;

  @override
  bool operator ==(Object other) =>
      other is LocalModuleReference && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

/// A module the generator cannot see into: a class annotated with
/// `@Module` in another package (its generated function), or a function
/// that returns an explicit `Module`. The graph check is partial for it;
/// the core checks the rest at startup.
final class OpaqueModuleReference extends ModuleReference {
  /// Creates the reference to the function [name] of [libraryUri],
  /// declared in [enclosingName] when it is a static method.
  const OpaqueModuleReference({
    required this.name,
    required this.libraryUri,
    this.enclosingName,
  });

  /// The function name.
  final String name;

  /// URI of the library that declares the function.
  final String libraryUri;

  /// The class that declares a static method; `null` for a top-level
  /// function.
  final String? enclosingName;

  @override
  String get display => enclosingName == null ? name : '$enclosingName.$name';

  @override
  bool operator ==(Object other) =>
      other is OpaqueModuleReference &&
      other.name == name &&
      other.libraryUri == libraryUri &&
      other.enclosingName == enclosingName;

  @override
  int get hashCode => Object.hash(name, libraryUri, enclosingName);
}
