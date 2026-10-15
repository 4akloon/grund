import 'dependency_model.dart';

/// How dependency injection calls the unnamed constructor of a provider or
/// `@Api` class.
final class ConstructorModel {
  /// A usable constructor with its [dependencies] in parameter order.
  const ConstructorModel(this.dependencies) : problem = null;

  /// A class that cannot be created, because of [problem].
  const ConstructorModel.invalid(String this.problem) : dependencies = const [];

  /// The parameters, in declaration order.
  final List<DependencyModel> dependencies;

  /// Why the class cannot be created, as a sentence; `null` when it can.
  final String? problem;
}
