import '../diagnostic/source_location.dart';

/// A `@Module` class declared in a `part of` file: the output is named after
/// the file of the declaration, which no library can import.
final class ModuleInPart {
  /// Creates the model.
  const ModuleInPart({required this.element, required this.location});

  /// The name of the module class.
  final String element;

  /// Where the class is declared.
  final SourceLocation location;
}
