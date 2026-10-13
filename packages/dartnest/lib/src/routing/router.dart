import 'pattern_segment.dart';
import 'route_match.dart';
import 'route_pattern.dart';
import 'routing_error.dart';

/// A segment trie (radix tree over path segments) mapping method + path to
/// a value.
///
/// Matching priority at every segment: static > `:param` > `*`, with
/// backtracking, so `/users/me` (static) and `/users/:id/posts` both work
/// and `DELETE /users/me` reaches `DELETE /users/:id` when the static route
/// has no `DELETE`. The result does not depend on insertion order. A router
/// is filled once at startup and only read afterwards.
final class Router<V> {
  /// Creates an empty router.
  Router();

  final _Node<V> _root = _Node<V>();

  /// Registers [value] for [method] and [pattern]; [source] describes the
  /// handler for [DuplicateRouteError].
  void add(
    String method,
    RoutePattern pattern,
    V value, {
    required String source,
  }) {
    var node = _root;
    for (final segment in pattern.segments) {
      node = node.child(segment);
    }
    final verb = method.toUpperCase();
    final existing = node.endpoints[verb];
    if (existing != null) {
      throw DuplicateRouteError(
        method: verb,
        path: pattern.toString(),
        existing: existing.source,
        duplicate: source,
      );
    }
    node.endpoints[verb] = _Endpoint(value, pattern.parameterNames, source);
  }

  /// Matches [method] against non-empty, decoded path [segments]. `HEAD`
  /// falls back to the `GET` route of the same path.
  RouteMatch<V> match(String method, List<String> segments) {
    final search = _Search<V>(segments, method.toUpperCase());
    final found = search.visit(_root, 0);
    if (found != null) return found;
    if (search.allowed.isEmpty) return RouteNotFound<V>();
    return RouteMethodNotAllowed<V>(search.allowed.toList()..sort());
  }
}

final class _Endpoint<V> {
  _Endpoint(this.value, this.parameterNames, this.source);

  final V value;
  final List<String> parameterNames;
  final String source;
}

final class _Node<V> {
  final Map<String, _Node<V>> statics = {};
  final Map<String, _Endpoint<V>> endpoints = {};
  _Node<V>? param;
  _Node<V>? wildcard;

  _Node<V> child(PatternSegment segment) => switch (segment) {
    StaticSegment(:final value) => statics.putIfAbsent(value, _Node<V>.new),
    ParamSegment() => param ??= _Node<V>(),
    WildcardSegment() => wildcard ??= _Node<V>(),
  };

  Set<String> get allowedMethods => {
    ...endpoints.keys,
    if (endpoints.containsKey('GET')) 'HEAD',
  };
}

/// One depth-first search; collects the methods of path matches that did
/// not accept [method], for 405.
final class _Search<V> {
  _Search(this.segments, this.method);

  final List<String> segments;
  final String method;
  final Set<String> allowed = {};
  final List<String> captured = [];

  RouteFound<V>? visit(_Node<V> node, int index) {
    if (index == segments.length) return _accept(node);
    final segment = segments[index];
    final exact = node.statics[segment];
    if (exact != null) {
      final found = visit(exact, index + 1);
      if (found != null) return found;
    }
    final param = node.param;
    if (param != null) {
      captured.add(segment);
      final found = visit(param, index + 1);
      captured.removeLast();
      if (found != null) return found;
    }
    final wildcard = node.wildcard;
    if (wildcard == null) return null;
    captured.add(segments.sublist(index).join('/'));
    final found = _accept(wildcard);
    captured.removeLast();
    return found;
  }

  RouteFound<V>? _accept(_Node<V> node) {
    final endpoint =
        node.endpoints[method] ??
        (method == 'HEAD' ? node.endpoints['GET'] : null);
    if (endpoint == null) {
      allowed.addAll(node.allowedMethods);
      return null;
    }
    return RouteFound<V>(
      endpoint.value,
      Map.fromIterables(endpoint.parameterNames, captured),
    );
  }
}
