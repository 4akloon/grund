import 'argument_source.dart';

/// Describes the argument a `Pipe` is transforming.
final class ArgumentMeta {
  /// Creates the description.
  const ArgumentMeta({
    required this.source,
    required this.name,
    required this.type,
  });

  /// Where the raw value comes from.
  final ArgumentSource source;

  /// Parameter name; `body` for the request body.
  final String name;

  /// The type the handler asked for.
  final Type type;
}
