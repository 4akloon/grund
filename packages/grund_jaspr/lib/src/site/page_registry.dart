import 'page_snapshot.dart';

/// Holds the current [PageSnapshot]; replaced when the runner reassembles.
final class PageRegistry {
  /// Creates an empty registry.
  PageRegistry();

  /// The latest snapshot; `null` until the runner has built one.
  PageSnapshot? current;

  /// Makes [snapshot] the current one.
  void replace(PageSnapshot snapshot) => current = snapshot;
}
