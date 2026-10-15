import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

Singleton<Tracked> tracked(String name, List<String> log) => Singleton<Tracked>(
  (i) {
    log.add('create $name');
    return Tracked(name, log);
  },
  name: name,
  dependsOn: const [],
);

ModuleGraph graphOf(List<Binding<Object>> bindings, {List<String>? log}) =>
    ModuleGraph.build(AppModule(bindings: bindings, log: log));

void main() {
  group('Container.reassemble', () {
    test('takes over a singleton whose module and key are unchanged', () async {
      final log = <String>[];
      final old = await Container.create(graphOf([tracked('db', log)]));
      final before = old.root<Tracked>('db');

      final next = await old.reassemble(graphOf([tracked('db', log)]));

      expect(next.root<Tracked>('db'), same(before));
      expect(log, ['create db']);
    });

    test(
      'creates a singleton that is new and keeps the taken over one',
      () async {
        final log = <String>[];
        final old = await Container.create(graphOf([tracked('db', log)]));

        final next = await old.reassemble(
          graphOf([tracked('db', log), tracked('cache', log)]),
        );

        expect(log, ['create db', 'create cache']);
        expect(next.root<Tracked>('cache'), isA<Tracked>());
      },
    );

    test('does not take over a binding that changed its scope', () async {
      final old = await Container.create(
        graphOf([Singleton<Clock>((i) => Clock(), dependsOn: const [])]),
      );
      final before = old.root<Clock>();

      final next = await old.reassemble(
        graphOf([Transient<Clock>((i) => Clock(), dependsOn: const [])]),
      );

      expect(next.root<Clock>(), isNot(same(before)));
    });

    test('does not init a module that is carried over again', () async {
      final log = <String>[];
      final old = await Container.create(graphOf(const [], log: log));
      log.clear();

      await old.reassemble(graphOf(const [], log: log));

      expect(log, isEmpty);
    });

    test('a failed reassemble leaves the old container working', () async {
      final log = <String>[];
      final old = await Container.create(graphOf([tracked('db', log)]));

      await expectLater(
        old.reassemble(
          graphOf([
            tracked('db', log),
            Singleton<Clock>(
              (i) => throw StateError('boom'),
              dependsOn: const [],
            ),
          ]),
        ),
        throwsA(isA<ProviderCreationError>()),
      );

      expect(old.root<Tracked>('db'), isA<Tracked>());
      expect(log, ['create db']);
    });

    test(
      'abandon disposes only what the new container created itself',
      () async {
        final log = <String>[];
        final old = await Container.create(graphOf([tracked('db', log)]));
        final next = await old.reassemble(
          graphOf([tracked('db', log), tracked('cache', log)]),
        );
        log.clear();

        await next.abandon();

        expect(log, ['dispose cache']);
      },
    );

    test(
      'closing the new container disposes the taken over singleton once',
      () async {
        final log = <String>[];
        final old = await Container.create(graphOf([tracked('db', log)]));
        final next = await old.reassemble(graphOf([tracked('db', log)]));
        log.clear();

        await next.close();

        expect(log, ['dispose db']);
      },
    );

    test(
      'abandon is idempotent and a close after it disposes nothing again',
      () async {
        final log = <String>[];
        final old = await Container.create(graphOf([tracked('db', log)]));
        final next = await old.reassemble(
          graphOf([tracked('db', log), tracked('cache', log)]),
        );
        log.clear();

        await next.abandon();
        await next.abandon();
        await next.close();

        expect(log, ['dispose cache']);
      },
    );
  });
}
