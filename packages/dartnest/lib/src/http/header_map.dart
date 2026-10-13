/// Case-insensitive multimap of HTTP header names to values.
///
/// Names are stored lower-cased; each name keeps its values in the order they
/// were added. A map made with [HeaderMap.unmodifiable] rejects changes,
/// which is how `HttpRequest` and `HttpResponse` stay immutable.
///
/// ```dart
/// final headers = HeaderMap.of({'Content-Type': 'application/json'});
/// headers['content-type']; // 'application/json'
/// headers.add('Set-Cookie', 'a=1');
/// headers.add('set-cookie', 'b=2');
/// headers.all('SET-COOKIE'); // ['a=1', 'b=2']
/// ```
final class HeaderMap {
  /// Creates an empty, modifiable map.
  HeaderMap() : this._({}, isReadOnly: false);

  /// Creates a modifiable map with one value per entry of [headers].
  factory HeaderMap.of(Map<String, String> headers) {
    final map = HeaderMap();
    headers.forEach(map.add);
    return map;
  }

  /// Creates a modifiable copy of [source].
  HeaderMap.copy(HeaderMap source)
    : this._(_copyValues(source._values), isReadOnly: false);

  /// Creates a read-only copy of [source].
  HeaderMap.unmodifiable(HeaderMap source)
    : this._(_copyValues(source._values), isReadOnly: true);

  HeaderMap._(this._values, {required this.isReadOnly});

  final Map<String, List<String>> _values;

  /// Whether changes are rejected with [UnsupportedError].
  final bool isReadOnly;

  /// The first value of [name], or `null` when the header is absent.
  String? operator [](String name) => _values[name.toLowerCase()]?.first;

  /// Every value of [name] in insertion order; empty when absent.
  List<String> all(String name) =>
      List.unmodifiable(_values[name.toLowerCase()] ?? const <String>[]);

  /// Whether [name] has at least one value.
  bool contains(String name) => _values.containsKey(name.toLowerCase());

  /// Lower-cased header names in insertion order.
  Iterable<String> get names => _values.keys;

  /// Appends [value] to the values of [name].
  void add(String name, String value) {
    _checkWritable();
    _values.putIfAbsent(name.toLowerCase(), () => []).add(value);
  }

  /// Replaces every value of [name] with [value].
  void set(String name, String value) {
    _checkWritable();
    _values[name.toLowerCase()] = [value];
  }

  /// Replaces the values of every name present in [other] with its values.
  void setAll(HeaderMap other) {
    _checkWritable();
    for (final MapEntry(:key, :value) in other._values.entries) {
      _values[key] = List.of(value);
    }
  }

  /// Removes every value of [name].
  void remove(String name) {
    _checkWritable();
    _values.remove(name.toLowerCase());
  }

  /// A read-only snapshot keyed by lower-cased name, for adapters that copy
  /// headers into their native response.
  Map<String, List<String>> toMap() => Map.unmodifiable({
    for (final MapEntry(:key, :value) in _values.entries)
      key: List<String>.unmodifiable(value),
  });

  void _checkWritable() {
    if (isReadOnly) {
      throw UnsupportedError('These headers are read-only; copy them first.');
    }
  }

  static Map<String, List<String>> _copyValues(
    Map<String, List<String>> source,
  ) => {
    for (final MapEntry(:key, :value) in source.entries) key: List.of(value),
  };
}
