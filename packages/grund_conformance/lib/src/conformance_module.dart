import 'package:grund/grund.dart';

import 'conformance_probe.dart';
import 'conformance_users.dart';
import 'probe_api.dart';
import 'users_api.dart';

/// The application every adapter serves in the conformance suite: a small
/// users API plus `/probe` routes that expose what the adapter delivered.
///
/// The module needs an `HttpModule` and an adapter module next to it; see
/// `ConformanceRoot`. [UsersApi] and [ProbeApi] describe the routes.
final class ConformanceModule extends Module {
  /// Creates the module around the [probe] the test holds.
  const ConformanceModule(this.probe);

  /// The probe of this server's fixture.
  final ConformanceProbe probe;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<ConformanceProbe>((_) => probe, dependsOn: const []),
    Singleton<ConformanceUsers>((_) => ConformanceUsers(), dependsOn: const []),
    Singleton<UsersApi>(
      (i) => UsersApi(i, i<ConformanceUsers>()),
      dependsOn: const [Key<ConformanceUsers>()],
    ),
    Singleton<ProbeApi>(
      (i) => ProbeApi(i, i<ConformanceProbe>()),
      dependsOn: const [Key<ConformanceProbe>()],
    ),
  ];
}
