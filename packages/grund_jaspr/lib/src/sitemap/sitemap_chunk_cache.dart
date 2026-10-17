/// A short-lived cache of the sitemap plan and of rendered sitemap chunks.
///
/// A value is stored only after its load succeeded, concurrent requests of
/// one key share one load, and at most [maxKeys] values are kept (the oldest
/// is evicted first).
final class SitemapChunkCache {
  /// Creates a cache whose values live [_lifetime], measured by [_clock].
  SitemapChunkCache(this._lifetime, this._clock);

  /// The most values the cache keeps.
  static const maxKeys = 64;

  final Duration _lifetime;
  final DateTime Function() _clock;

  // Dart maps keep insertion order, so the first key is the oldest.
  final Map<String, ({Object value, DateTime expires})> _stored = {};
  final Map<String, Future<Object>> _pending = {};
  var _generation = 0;

  /// The value of [key]: the stored one while it is fresh, the one a
  /// concurrent request is loading, or the result of [load].
  Future<T> get<T extends Object>(String key, Future<T> Function() load) async {
    final hit = _stored[key];
    if (hit != null) {
      if (_clock().isBefore(hit.expires)) return hit.value as T;
      _stored.remove(key);
    }
    final pending = _pending[key];
    if (pending != null) return await pending as T;
    final fill = _fill(key, load);
    _pending[key] = fill;
    return fill;
  }

  /// Drops every stored value and forgets loads in progress, so a value
  /// that is being loaded is not stored.
  void clear() {
    _generation++;
    _stored.clear();
    _pending.clear();
  }

  Future<T> _fill<T extends Object>(
    String key,
    Future<T> Function() load,
  ) async {
    final generation = _generation;
    try {
      // `Future.sync` makes a throwing [load] fail asynchronously, after
      // the pending entry was recorded.
      final value = await Future<T>.sync(load);
      if (generation == _generation) _store(key, value);
      return value;
    } finally {
      if (generation == _generation) _pending.remove(key);
    }
  }

  void _store(String key, Object value) {
    _stored.remove(key);
    _stored[key] = (value: value, expires: _clock().add(_lifetime));
    while (_stored.length > maxKeys) {
      _stored.remove(_stored.keys.first);
    }
  }
}
