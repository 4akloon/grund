import '../diagnostic/source_location.dart';
import 'provider_key.dart';

/// A constructor parameter that dependency injection fills.
///
/// Exactly one of [key] and [problem] is set.
final class DependencyModel {
  /// A parameter resolved by [key].
  const DependencyModel.injected({
    required this.name,
    required this.isNamed,
    required this.location,
    required ProviderKey this.key,
  }) : problem = null;

  /// A parameter that cannot be injected, because of [problem].
  const DependencyModel.invalid({
    required this.name,
    required this.isNamed,
    required this.location,
    required String this.problem,
  }) : key = null;

  /// The parameter name.
  final String name;

  /// Whether the parameter is named (passed as `name: value`).
  final bool isNamed;

  /// Where the parameter is declared.
  final SourceLocation location;

  /// The provider key to resolve; `null` when [problem] is set.
  final ProviderKey? key;

  /// Why the parameter cannot be injected, as a sentence.
  final String? problem;
}
