import 'package:grund/grund.dart';

import 'in_memory_session_store.dart';
import 'session_config.dart';
import 'session_store.dart';
import 'sessions.dart';

/// Cookie sessions: binds [SessionConfig], [SessionStore] and [Sessions],
/// globally, so every API sees them.
///
/// ```dart
/// imports: [
///   const HttpModule(),
///   const SessionModule(config: SessionConfig(secure: false)), // dev only
/// ]
/// ```
///
/// [config] is validated when the application starts; an invalid one
/// throws [SessionConfigError] before the server serves.
final class SessionModule extends Module {
  /// Sessions with [config], kept in the store [store] creates.
  const SessionModule({
    this.config = const SessionConfig(),
    this.store = InMemorySessionStore.new,
  });

  /// The cookie and the same-origin check.
  final SessionConfig config;

  /// Creates the store, once per application.
  final SessionStore Function() store;

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<SessionConfig>((_) => config, dependsOn: const []),
    Singleton<SessionStore>((_) => store(), dependsOn: const []),
    Singleton<Sessions>(
      (i) => Sessions(i<SessionStore>(), i<SessionConfig>()),
      dependsOn: const [Key<SessionStore>(), Key<SessionConfig>()],
    ),
  ];

  @override
  List<Object> get exports => const [
    Key<SessionConfig>(),
    Key<SessionStore>(),
    Key<Sessions>(),
  ];

  @override
  void onInit(Injector injector) => config.validate();
}
