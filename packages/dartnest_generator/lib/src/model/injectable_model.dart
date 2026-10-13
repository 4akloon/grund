import '../diagnostic/source_location.dart';
import 'constructor_model.dart';
import 'type_model.dart';

/// A class that a module provides through its constructor: a class in
/// `@Module(providers: ...)` or the implementation of a `Bind`.
final class InjectableModel {
  /// Creates the model.
  const InjectableModel({
    required this.type,
    required this.isAnnotated,
    required this.constructor,
    required this.location,
    this.documentation,
  });

  /// The class.
  final TypeModel type;

  /// Whether the class is annotated with `@Injectable()`.
  final bool isAnnotated;

  /// How to create an instance.
  final ConstructorModel constructor;

  /// Where the class is declared.
  final SourceLocation location;

  /// The `///` comment of the class, if any.
  final String? documentation;
}
