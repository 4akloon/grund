/// Stack of keys currently being resolved. Shared by all injectors of one
/// container so that chains crossing module boundaries stay complete.
final class ResolutionTrace {
  final List<Object> _stack = [];

  /// Keys being resolved, innermost first.
  List<Object> get snapshot => List.unmodifiable(_stack.reversed);

  /// Marks [key] as being resolved.
  void push(Object key) => _stack.add(key);

  /// Removes the innermost key.
  void pop() => _stack.removeLast();

  /// The cycle starting at [key], for `CircularDependencyError`. When [key]
  /// is not on the stack (a factory re-entered itself after an `await`), the
  /// cycle is reported as `[key, key]`.
  List<Object> cycleFrom(Object key) {
    final start = _stack.indexOf(key);
    if (start < 0) return [key, key];
    return [..._stack.sublist(start), key];
  }
}
