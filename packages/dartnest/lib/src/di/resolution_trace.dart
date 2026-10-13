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

  /// Whether [key] is being resolved right now.
  bool contains(Object key) => _stack.contains(key);

  /// The cycle starting at [key], for `CircularDependencyError`. [key] must
  /// be on the stack (check [contains] first).
  List<Object> cycleFrom(Object key) {
    final start = _stack.indexOf(key);
    return [..._stack.sublist(start), key];
  }
}
