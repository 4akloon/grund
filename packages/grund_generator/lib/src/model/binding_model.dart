import '../diagnostic/source_location.dart';
import 'binding_key.dart';
import 'dependency_model.dart';
import 'lifetime.dart';

/// A binding a module owns, as the graph checks see it: its key, lifetime
/// and what it resolves, whether it comes from a class or a `@Provides`
/// method.
final class BindingModel {
  /// Creates the binding.
  const BindingModel({
    required this.key,
    required this.lifetime,
    required this.dependencies,
    required this.location,
  });

  /// What the binding is looked up by.
  final BindingKey key;

  /// How long the instances live.
  final Lifetime lifetime;

  /// What the factory resolves, in parameter order.
  final List<DependencyModel> dependencies;

  /// Where the binding is declared.
  final SourceLocation location;
}
