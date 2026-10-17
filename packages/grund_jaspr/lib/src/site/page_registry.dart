import 'page_snapshot.dart';

/// Holds the current [PageSnapshot]; replaced when the runner reassembles.
final class PageRegistry {
  /// Creates an empty registry.
  PageRegistry();

  PageSnapshot? _current;
  var _generation = 0;

  /// The latest snapshot; `null` until the runner has built one.
  PageSnapshot? get current => _current;

  /// The number of snapshots stored so far; it grows with every [replace],
  /// so it tells two snapshots apart. Read it together with [current], in
  /// one synchronous step.
  int get generation => _generation;

  /// Makes [snapshot] the current one.
  void replace(PageSnapshot snapshot) {
    _current = snapshot;
    _generation++;
  }
}
