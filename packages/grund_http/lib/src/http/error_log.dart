/// Receives the errors that become 500 responses, with their stack traces.
///
/// It must not throw. `HttpModule` binds [LoggingErrorLog], which logs on
/// `grund.http`; bind another implementation under `Key<ErrorLog>()` (an
/// override in tests, an error tracker in production) to take the reports
/// elsewhere.
abstract interface class ErrorLog {
  /// Records [error] that was turned into a 500 response.
  void report(Object error, StackTrace stackTrace);
}
