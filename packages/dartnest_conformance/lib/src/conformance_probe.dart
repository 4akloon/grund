import 'dart:async';

/// Lets a test hold the fixture's slow handlers and observe its streams.
///
/// Created per test by `ConformanceServer.start`; every completer is used
/// at most once.
final class ConformanceProbe {
  /// Completes when `GET /probe/slow` or `GET /probe/gated-stream` starts
  /// waiting for [release].
  final Completer<void> entered = Completer<void>();

  /// Completed by the test to let the waiting handler or stream finish.
  final Completer<void> release = Completer<void>();

  /// Completes when `POST /probe/upload` received its first chunk.
  final Completer<void> firstUploadChunk = Completer<void>();

  /// Completes when the subscription to the `GET /probe/endless` stream is
  /// cancelled.
  final Completer<void> endlessCancelled = Completer<void>();
}
