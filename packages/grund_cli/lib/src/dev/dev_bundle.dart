import 'dart:io';

import '../bundle/bundle_result.dart';
import '../bundle/client_bundler.dart';
import '../bundle/compile_runner.dart';

/// Keeps the client bundle of `dev` up to date: builds it (`-O1` with source
/// maps), merges the requests that arrive during a build into one more
/// build, and prints the outcome.
///
/// A failing build (compiler errors, IO failures) is printed, never thrown:
/// the old bundle keeps serving. After [close] nothing more is built or
/// printed.
final class DevBundle {
  /// Creates the bundle of [bundler] that reports to `out`.
  DevBundle(this.bundler, {required this._out});

  /// What compiles and moves the bundle into place.
  final ClientBundler bundler;

  final StringSink _out;
  Future<void>? _running;
  var _rebuildWanted = false;
  var _closed = false;

  /// Builds the bundle and completes when it is done, whatever the outcome;
  /// `dev` awaits it before serving, so the first page load finds the bundle.
  Future<void> initial() {
    request();
    return settled;
  }

  /// Starts a build; while one runs, asks for exactly one more after it
  /// (requests merge).
  void request() {
    if (_closed) return;
    if (_running != null) {
      _rebuildWanted = true;
      return;
    }
    _running = _drain();
  }

  /// Ends the bundle for `dev`'s shutdown: a build that is still running is
  /// not cancelled (the compiler child cannot be stopped through
  /// [CompileRunner]), but it finishes silently and no further one starts.
  void close() => _closed = true;

  /// Completes when no build runs and none is waiting.
  Future<void> get settled => _running ?? Future<void>.value();

  Future<void> _drain() async {
    try {
      do {
        _rebuildWanted = false;
        await _buildOnce();
      } while (_rebuildWanted && !_closed);
    } finally {
      _running = null;
    }
  }

  Future<void> _buildOnce() async {
    try {
      final result = await bundler.build(release: false);
      if (_closed) return;
      switch (result) {
        case BundleBuilt(:final elapsed):
          _out.writeln(
            'Bundled ${bundler.outputDirectory}/${bundler.outputName} in '
            '${elapsed.inMilliseconds} ms.',
          );
        case BundleSkipped():
          break;
        case BundleFailed(:final output):
          _out.writeln(
            'Client bundle failed; the previous one stays:\n$output',
          );
      }
    } on IOException catch (error) {
      if (_closed) return;
      _out.writeln('Client bundle failed; the previous one stays:\n$error');
    }
  }
}
