/// A provider for the key [K] created by the `Injectable` class [I].
///
/// ```dart
/// @Module(providers: [Bind<Clock, SystemClock>()])
/// class TimeModule {}
/// ```
final class Bind<K extends Object, I extends K> {
  /// Creates the binding.
  const Bind();
}
