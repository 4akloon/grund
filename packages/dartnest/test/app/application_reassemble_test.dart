import 'dart:async';
import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/http_fixtures.dart';

final class Answer {
  Answer(this.clock, this.text);
  final Clock clock;
  final String text;
}

/// The application's module function reads this, the way a module
/// function reads the code a hot reload replaced.
final class Version {
  /// The answer of `GET /answer`.
  static String text = 'old';

  /// The paths of the routes, each answering [text].
  static List<String> paths = ['/answer'];

  /// Holds `GET /answer` until it completes.
  static Completer<void> gate = Completer<void>()..complete();

  /// The module of the current version.
  static Module module() => Module(
    id: 'app',
    providers: [Provider((i) => Clock())],
    controllers: [
      Controller<Answer>(
        create: (i) => Answer(i.get(), text),
        routes: [
          for (final path in paths)
            Route.get(path, (c, ctx) async {
              await gate.future;
              return c.text;
            }),
        ],
      ),
    ],
  );
}

Future<String> textOf(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

void main() {
  setUp(() {
    Version.text = 'old';
    Version.paths = ['/answer'];
    Version.gate = Completer<void>()..complete();
  });

  group('Application.reassemble', () {
    test('serves the routes of the new module function', () async {
      final app = await Application.create(Version.module);
      Version.text = 'new';
      Version.paths = ['/reply'];

      final report = await app.reassemble();

      expect(
        await textOf(await app.handle(requestFor('GET', '/reply'))),
        'new',
      );
      expect((await app.handle(requestFor('GET', '/answer'))).status, 404);
      expect(report.addedRoutes, ['GET /reply']);
      expect(report.removedRoutes, ['GET /answer']);
      expect(report.changedRoutes, 2);
    });

    test('keeps the instances of providers that stay', () async {
      final app = await Application.create(Version.module);
      final clock = app.container.root.get<Clock>();

      await app.reassemble();

      expect(app.container.root.get<Clock>(), same(clock));
    });

    test('a request keeps the table it started with', () async {
      // Review Focus 2: a reload while a request is in flight.
      Version.gate = Completer<void>();
      final app = await Application.create(Version.module);
      app.use((request, next) async {
        await Future<void>.delayed(Duration.zero);
        return next();
      });

      final inFlight = app.handle(requestFor('GET', '/answer'));
      Version.text = 'new';
      await app.reassemble();
      final after = app.handle(requestFor('GET', '/answer'));
      Version.gate.complete();

      expect(await textOf(await inFlight), 'old');
      expect(await textOf(await after), 'new');
    });

    test('a failure keeps the previous routes and container', () async {
      final app = await Application.create(Version.module);
      final container = app.container;
      Version.paths = ['/answer', '/answer'];

      await expectLater(app.reassemble(), throwsA(isA<RoutingError>()));
      expect(app.container, same(container));
      expect(
        await textOf(await app.handle(requestFor('GET', '/answer'))),
        'old',
      );
      Version.paths = ['/answer'];
      expect(await app.reassemble(), isA<ReassembleReport>());
    });

    test('a module function that throws is passed on', () async {
      var calls = 0;
      final app = await Application.create(() {
        if (++calls > 1) throw StateError('broken module');
        return Version.module();
      });

      await expectLater(app.reassemble(), throwsA(isA<StateError>()));
      expect((await app.handle(requestFor('GET', '/answer'))).status, 200);
    });

    test('a module value is reassembled with the same routes', () async {
      final app = await Application.fromModule(Version.module());

      final report = await app.reassemble();

      expect(report.changedRoutes, 0);
    });

    test('fails while another reassemble runs and after close', () async {
      final app = await Application.create(Version.module);

      final first = app.reassemble();
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
      await first;
      await app.close();
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
    });
  });
}
