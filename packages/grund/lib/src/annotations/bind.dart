/// A binding of the interface [I] created by the `Injectable` class [C].
///
/// ```dart
/// @Module(providers: [Bind<Clock, SystemClock>()])
/// final class TimeModule extends grund.Module with $TimeModule {
///   const TimeModule();
/// }
/// ```
final class Bind<I extends Object, C extends I> {
  /// Creates the binding.
  const Bind();
}
