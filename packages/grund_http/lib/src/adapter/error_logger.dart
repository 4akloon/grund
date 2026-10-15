/// Receives errors that become 500 responses, with their stack traces.
///
/// It must not throw: a throwing logger is reported to the adapter's own
/// error callback and the response is still sent.
typedef ErrorLogger = void Function(Object error, StackTrace stackTrace);
