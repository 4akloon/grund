/// Marker for everything that can be listed in `Enhancers`: guards,
/// interceptors, pipes, exception filters, and `Use` references to them.
///
/// Implement `Guard`, `Interceptor`, `Pipe` or extend `ExceptionFilter`
/// rather than this type directly.
abstract interface class PipelineComponent {}
