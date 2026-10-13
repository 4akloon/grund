import '../http/http_exception.dart';
import '../http/request_body.dart';
import 'argument_meta.dart';
import 'argument_resolver.dart';
import 'argument_source.dart';
import 'pipe.dart';
import 'pipeline_error.dart';
import 'transport.dart';

/// Everything the pipeline knows about the request being handled; passed to
/// guards, interceptors, filters and handlers.
///
/// One context is created per request, after routing. Arguments are read
/// with [param], [query] and [bodyAs], which run the pipes and convert the
/// value:
///
/// ```dart
/// Route.get('/:id', (c, ctx) async => c.findOne(await ctx.param<int>('id')));
/// ```
final class ExecutionContext {
  /// Creates a context. [metadata] is ordered most specific first (route,
  /// then controller); [pipes] are the resolved application, controller and
  /// route pipes in that order.
  ExecutionContext({
    required this.transport,
    required this.controllerType,
    required this.handlerName,
    List<Object> metadata = const [],
    List<Pipe<Object?, Object?>> pipes = const [],
  }) : _metadata = metadata,
       _pipes = pipes;

  /// The protocol of the request.
  final Transport transport;

  /// The controller class that declares the handler.
  final Type controllerType;

  /// Name of the handler (the route's `name`).
  final String handlerName;

  /// Free-form storage for passing data between guards, interceptors and
  /// the handler (for example the authenticated user).
  final Map<Object, Object?> items = {};

  final List<Object> _metadata;
  final List<Pipe<Object?, Object?>> _pipes;

  /// The HTTP view of the request.
  HttpContext switchToHttp() => switch (transport) {
    HttpContext http => http,
  };

  /// The first metadata value of type [T]: route metadata overrides
  /// controller metadata. `null` when neither declares one.
  T? metadata<T extends Object>() {
    for (final value in _metadata) {
      if (value is T) return value;
    }
    return null;
  }

  /// The first value of request header [name] (case-insensitive).
  String? header(String name) => switchToHttp().request.headers[name];

  /// The raw request body, read once and cached.
  RequestBody get body => switchToHttp().request.body;

  /// Path parameter [name] as [T], after the configured [pipes] and the
  /// call's own [pipes]. A name the route does not declare throws
  /// [UnknownRouteParameterError]; an unparsable value throws
  /// [BadRequestException].
  Future<T> param<T>(
    String name, {
    List<Pipe<Object?, Object?>> pipes = const [],
  }) async {
    final parameters = switchToHttp().pathParameters;
    final raw = parameters[name];
    if (raw == null) {
      throw UnknownRouteParameterError(
        name: name,
        handlerName: handlerName,
        declared: parameters.keys.toList(),
      );
    }
    return ArgumentResolver.resolve<T>(
      raw,
      ArgumentMeta(source: ArgumentSource.path, name: name, type: T),
      [..._pipes, ...pipes],
    );
  }

  /// Query parameter [name] (its first value) as [T]. An absent parameter
  /// is `null` for a nullable [T] and a [BadRequestException] otherwise.
  Future<T> query<T>(
    String name, {
    List<Pipe<Object?, Object?>> pipes = const [],
  }) {
    final values = switchToHttp().request.uri.queryParametersAll[name];
    return ArgumentResolver.resolve<T>(
      values == null || values.isEmpty ? null : values.first,
      ArgumentMeta(source: ArgumentSource.query, name: name, type: T),
      [..._pipes, ...pipes],
    );
  }

  /// The JSON body decoded with [fromJson], after the pipes ran on the
  /// decoded JSON. A body that is not a JSON object, malformed JSON, or a
  /// [FormatException] thrown by [fromJson] is a [BadRequestException].
  Future<T> bodyAs<T>(
    T Function(Map<String, Object?> json) fromJson, {
    List<Pipe<Object?, Object?>> pipes = const [],
  }) async {
    final meta = ArgumentMeta(
      source: ArgumentSource.body,
      name: 'body',
      type: T,
    );
    final value = await ArgumentResolver.pipe(await body.json(), meta, [
      ..._pipes,
      ...pipes,
    ]);
    if (value is T) return value;
    if (value is! Map<String, Object?>) {
      throw const BadRequestException(
        message: 'Request body must be a JSON object.',
      );
    }
    try {
      return fromJson(value);
    } on FormatException catch (error) {
      throw BadRequestException(
        message: 'Invalid request body: ${error.message}',
      );
    }
  }
}
