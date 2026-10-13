import '../diagnostic/source_location.dart';
import 'parameter_binding.dart';
import 'type_model.dart';

/// A parameter of a route handler method.
final class HandlerParameter {
  /// Creates the model.
  const HandlerParameter({
    required this.name,
    required this.type,
    required this.binding,
    required this.isNamed,
    required this.location,
  });

  /// The parameter name.
  final String name;

  /// The declared type.
  final TypeModel type;

  /// Where the value comes from.
  final ParameterBinding binding;

  /// Whether the parameter is named.
  final bool isNamed;

  /// Where the parameter is declared.
  final SourceLocation location;
}
