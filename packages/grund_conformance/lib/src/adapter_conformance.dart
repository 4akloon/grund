import 'package:test/test.dart';

import 'adapter_under_test.dart';
import 'groups/body_conformance.dart';
import 'groups/lifecycle_conformance.dart';
import 'groups/request_conformance.dart';

/// Entry point of the shared suite: an adapter package calls [run] from a
/// test file.
///
/// ```dart
/// void main() => AdapterConformance.run(
///   'IoAdapter',
///   (onError, closeTimeout) {
///     final adapter = IoAdapter(
///       onError: onError,
///       closeTimeout: closeTimeout,
///     );
///     return AdapterUnderTest(adapter, boundPort: () => adapter.port);
///   },
/// );
/// ```
abstract final class AdapterConformance {
  /// Registers every conformance group for the adapters [factory] creates,
  /// inside a group called [name].
  static void run(String name, AdapterFactory factory) {
    group('$name conformance', () {
      RequestConformance.register(factory);
      BodyConformance.register(factory);
      LifecycleConformance.register(factory);
    });
  }
}
