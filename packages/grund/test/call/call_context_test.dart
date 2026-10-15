import 'package:grund/src/call/call_context.dart';
import 'package:grund/src/call/cancel_signal.dart';
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

Future<CallContext> openContext(
  List<Binding<Object>> bindings, {
  CancelSignal? cancel,
}) async {
  final container = await Container.create(
    ModuleGraph.build(AppModule(bindings: bindings)),
  );
  return CallContext(container.root.openCall(), cancel: cancel);
}

void main() {
  group('CallContext', () {
    test('resolves singletons and scoped bindings of its module', () async {
      final context = await openContext([
        Singleton<Clock>((i) => Clock(), dependsOn: const []),
        Scoped<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
      ]);

      expect(context<Repo>().clock, same(context<Clock>()));
      expect(context.maybe<Secret>(), isNull);
    });

    test('a value set by a hook is found by type', () async {
      final context = await openContext(const []);
      final secret = Secret();

      context.set<Secret>(secret);

      expect(context<Secret>(), same(secret));
    });

    test('a named value does not answer for the unnamed one', () async {
      final context = await openContext(const []);

      context.set<Secret>(Secret(), name: 'admin');

      expect(context.maybe<Secret>(), isNull);
      expect(context.maybe<Secret>('admin'), isNotNull);
    });

    test('close disposes the scoped instances of the call', () async {
      final log = <String>[];
      final context = await openContext([
        Scoped<Tracked>((i) => Tracked('tx', log), dependsOn: const []),
      ]);
      context<Tracked>();

      await context.close();

      expect(log, ['dispose tx']);
    });

    test('has its own cancel signal unless one is given', () async {
      final own = await openContext(const []);
      final given = CancelSignal();
      final shared = await openContext(const [], cancel: given);

      expect(own.cancel.isCancelled, isFalse);
      expect(shared.cancel, same(given));
    });
  });
}
