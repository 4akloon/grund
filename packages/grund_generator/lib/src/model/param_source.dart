import 'binding_key.dart';
import 'body_kind.dart';
import 'invalid_source_reason.dart';
import 'param_location.dart';
import 'value_kind.dart';

/// Where the value of a route parameter comes from.
sealed class ParamSource {
  /// Creates the source.
  const ParamSource();
}

/// A named value of the request.
final class ValueSource extends ParamSource {
  /// Creates the source.
  const ValueSource(this.location, this.name, this.kind);

  /// The request part.
  final ParamLocation location;

  /// The name in the request.
  final String name;

  /// The type of the value.
  final ValueKind kind;
}

/// `@Body()`.
final class BodySource extends ParamSource {
  /// Creates the source.
  const BodySource(this.kind);

  /// How the body is read.
  final BodyKind kind;
}

/// A parameter of type `HttpCtx`: the context itself.
final class ContextSource extends ParamSource {
  /// Creates the source.
  const ContextSource();
}

/// A parameter without annotation: a value of the call scope, resolved by
/// its type (`c<T>()`).
final class CallScopeSource extends ParamSource {
  /// Creates the source.
  const CallScopeSource(this.key);

  /// The value looked up.
  final BindingKey key;
}

/// A parameter that cannot be filled, because of [problem].
final class InvalidSource extends ParamSource {
  /// Creates the source.
  const InvalidSource(this.reason, this.problem);

  /// The kind of problem; it selects the diagnostic code.
  final InvalidSourceReason reason;

  /// Why the parameter has no source, as a sentence fragment.
  final String problem;
}
