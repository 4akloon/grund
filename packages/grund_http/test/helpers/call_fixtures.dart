import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';

/// Counts the lifecycle of [Tx] instances.
final class TxLog {
  /// Instances created.
  int created = 0;

  /// Instances disposed.
  int disposed = 0;
}

/// A call-scoped resource that is disposed after the request.
final class Tx implements Disposable {
  Tx(this._log, {this.failOnDispose = false}) {
    _log.created++;
  }

  final TxLog _log;
  final bool failOnDispose;

  @override
  void dispose() {
    _log.disposed++;
    if (failOnDispose) throw StateError('cannot close the transaction');
  }
}

/// What a hook hands to the handler with `c.set`.
final class CurrentUser {
  CurrentUser(this.name);

  final String name;
}

/// Sets [CurrentUser] from the `x-user` header.
final class UserHook extends HttpHook {
  const UserHook();

  @override
  void before(HttpCtx c) =>
      c.set<CurrentUser>(CurrentUser(c.headers.string('x-user')));
}

/// The bindings the call tests share.
List<Binding<Object>> callBindings({bool failOnDispose = false}) => [
  Singleton<TxLog>((i) => TxLog(), dependsOn: const []),
  Scoped<Tx>(
    (i) => Tx(i<TxLog>(), failOnDispose: failOnDispose),
    dependsOn: const [Key<TxLog>()],
  ),
  Singleton<UserHook>((i) => const UserHook(), dependsOn: const []),
];
