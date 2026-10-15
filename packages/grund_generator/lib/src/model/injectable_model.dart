import '../diagnostic/source_location.dart';
import 'binding_key.dart';
import 'constructor_model.dart';
import 'lifetime.dart';
import 'type_model.dart';

/// A class that a module provides through its constructor: a class in
/// `@Module(providers: ...)` or the implementation of a `Bind`.
final class InjectableModel {
  /// Creates the model.
  const InjectableModel({
    required this.type,
    required this.lifetime,
    required this.isAnnotated,
    required this.constructor,
    required this.location,
    this.name,
    this.isApi = false,
    this.scopeProblem,
    this.documentation,
  });

  /// The class.
  final TypeModel type;

  /// The `@Named` qualifier of the class, or `null`.
  final String? name;

  /// The lifetime of the binding.
  final Lifetime lifetime;

  /// Whether the class is annotated with `@Injectable()` or `@Api(...)`.
  final bool isAnnotated;

  /// Whether the class is annotated with `@Api(...)`.
  final bool isApi;

  /// Why the `scope` of `@Injectable` is unusable, as a sentence; `null`
  /// when it is fine.
  final String? scopeProblem;

  /// How to create an instance.
  final ConstructorModel constructor;

  /// Where the class is declared.
  final SourceLocation location;

  /// The `///` comment of the class, if any.
  final String? documentation;

  /// The key under which the class is bound when it is bound as itself.
  BindingKey get key => BindingKey(type, name);
}
