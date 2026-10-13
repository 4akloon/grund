import 'package:dartnest/dartnest.dart';

/// Creates the adapter under test; [onError] receives the failures the
/// adapter reports itself (a throwing handler, a failing body stream), and
/// [closeTimeout] is the adapter's limit for a graceful close (`null`: no
/// limit).
typedef AdapterFactory =
    AdapterUnderTest Function(ErrorLogger onError, Duration? closeTimeout);

/// An adapter for the conformance suite and how to read the port it bound;
/// the suite always listens on port 0.
final class AdapterUnderTest {
  /// Wraps [adapter]; [boundPort] is called after `listen` completed.
  const AdapterUnderTest(this.adapter, {required this.boundPort});

  /// The adapter passed to `Application.create`.
  final HttpAdapter adapter;

  /// The port the adapter listens on.
  final int Function() boundPort;
}
