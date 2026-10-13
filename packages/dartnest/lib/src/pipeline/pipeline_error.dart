import '../di/errors.dart';
import 'argument_meta.dart';

/// Programming errors detected while a request runs through the pipeline.
/// They reach the client as 500.
sealed class PipelineError extends DartnestError {
  /// Creates a pipeline error.
  const PipelineError();
}

/// A handler asked for an argument type that has no built-in conversion and
/// no pipe produced it.
final class UnsupportedConversionError extends PipelineError {
  /// Creates the error.
  const UnsupportedConversionError({
    required this.argument,
    required this.valueType,
  });

  /// The argument and the requested type.
  final ArgumentMeta argument;

  /// Runtime type of the value the pipes produced.
  final Type valueType;

  @override
  String get message =>
      'Cannot convert ${argument.source.label} "${argument.name}" from '
      '$valueType to ${argument.type}. Built-in conversion supports String, '
      'int, double, num, bool and DateTime; add a Pipe that returns '
      '${argument.type}.';
}

/// A handler read a path parameter that its route does not declare.
final class UnknownRouteParameterError extends PipelineError {
  /// Creates the error.
  const UnknownRouteParameterError({
    required this.name,
    required this.handlerName,
    required this.declared,
  });

  /// The requested parameter.
  final String name;

  /// The handler that asked for it.
  final String handlerName;

  /// Parameters the route declares.
  final List<String> declared;

  @override
  String get message =>
      'Handler "$handlerName" reads path parameter "$name", but its route '
      'declares ${declared.isEmpty ? 'none' : declared.join(', ')}.';
}

/// A handler result cannot be encoded as JSON.
final class SerializationError extends PipelineError {
  /// Creates the error.
  const SerializationError({required this.valueType, this.cause});

  /// Runtime type of the value that could not be encoded.
  final Type valueType;

  /// What the JSON encoder reported, if anything.
  final Object? cause;

  @override
  String get message =>
      'Cannot serialize $valueType to JSON'
      '${cause == null ? '' : ' ($cause)'}. Give it a toJson() method, '
      'return an HttpResponse, or register a serializer with '
      'app.serializers.register<$valueType>(...).';
}
