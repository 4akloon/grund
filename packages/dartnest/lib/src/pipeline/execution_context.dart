import '../http/request_body.dart';
import 'transport.dart';

/// Everything the pipeline knows about the request being handled; passed to
/// guards, interceptors, filters and handlers.
///
/// One context is created per request, after routing.
final class ExecutionContext {
  /// Creates a context. [metadata] is ordered most specific first (route,
  /// then controller).
  ExecutionContext({
    required this.transport,
    required this.controllerType,
    required this.handlerName,
    List<Object> metadata = const [],
  }) : _metadata = metadata;

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
}
