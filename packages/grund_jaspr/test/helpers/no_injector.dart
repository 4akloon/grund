import 'package:grund/grund.dart';

/// An [Injector] for tests that never resolve anything.
///
/// `noSuchMethod` is the shortest way to implement the whole interface: any
/// call fails loudly instead of returning a value.
final class NoInjector implements Injector {
  /// Creates the injector.
  const NoInjector();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
