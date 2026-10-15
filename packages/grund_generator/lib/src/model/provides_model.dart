import '../diagnostic/source_location.dart';
import 'binding_key.dart';
import 'dependency_model.dart';
import 'lifetime.dart';
import 'type_model.dart';

/// A `static` method of a module class annotated with `@Provides`.
final class ProvidesModel {
  /// Creates the model.
  const ProvidesModel({
    required this.owner,
    required this.methodName,
    required this.location,
    this.key,
    this.lifetime = Lifetime.singleton,
    this.isAsync = false,
    this.dependencies = const [],
    this.documentation,
    this.problem,
  });

  /// The class that declares the method.
  final TypeModel owner;

  /// The method name.
  final String methodName;

  /// Where the method is declared.
  final SourceLocation location;

  /// The binding the method provides: its return type (without `Future`)
  /// and `@Named`; `null` when [problem] is set.
  final BindingKey? key;

  /// The lifetime of the binding.
  final Lifetime lifetime;

  /// Whether the method returns a `Future` or `FutureOr`.
  final bool isAsync;

  /// The parameters, in declaration order.
  final List<DependencyModel> dependencies;

  /// The `///` comment of the method, if any.
  final String? documentation;

  /// Why the method cannot provide a binding, as a sentence; `null` when it
  /// can.
  final String? problem;
}
