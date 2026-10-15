import 'package:grund_http/grund_http.dart';

/// An [ErrorLog] that keeps what it was given.
final class RecordingErrorLog implements ErrorLog {
  /// The reported errors, oldest first.
  final List<Object> errors = [];

  @override
  void report(Object error, StackTrace stackTrace) => errors.add(error);
}
