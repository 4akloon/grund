import 'package:grund_http/grund_http.dart';

/// In-memory users of the conformance application.
final class ConformanceUsers {
  final Map<int, String> _names = {1: 'ann', 2: 'bob'};

  /// The user with [id] as JSON; [NotFoundException] when absent.
  Map<String, Object?> find(int id) => switch (_names[id]) {
    final name? => {'id': id, 'name': name},
    null => throw NotFoundException(message: 'No user $id'),
  };

  /// Adds a user called [name] and returns it as JSON.
  Map<String, Object?> create(String name) {
    final id = _names.length + 1;
    _names[id] = name;
    return find(id);
  }
}
