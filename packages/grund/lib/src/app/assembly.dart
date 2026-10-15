import '../di/container.dart';
import '../pipeline/endpoint.dart';
import '../routing/router.dart';

/// The started container of an application and the route table built from
/// it. Internal: it is not exported from the barrel.
final class Assembly {
  /// Pairs a started [container] with the [router] built from it.
  const Assembly({required this.container, required this.router});

  /// The started dependency container.
  final Container container;

  /// The route table whose controllers come from [container].
  final Router<Endpoint> router;
}
