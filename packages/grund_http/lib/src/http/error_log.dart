/// Receives the errors that become 500 responses, with their stack traces.
///
/// It must not throw. `HttpModule` binds [PrintErrorLog]; bind another
/// implementation under `Key<ErrorLog>()` (an override in tests, a logger in
/// production) to take the reports elsewhere.
abstract interface class ErrorLog {
  /// Records [error] that was turned into a 500 response.
  void report(Object error, StackTrace stackTrace);
}
