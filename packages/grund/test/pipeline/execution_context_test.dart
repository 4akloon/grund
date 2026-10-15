import 'package:grund/grund.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

final class Roles {
  const Roles(this.names);
  final List<String> names;
}

final class Public {
  const Public();
}

final class AllowAll implements Guard {
  @override
  bool canActivate(ExecutionContext context) => true;
}

final class StateErrorFilter extends ExceptionFilter<StateError> {
  const StateErrorFilter();

  @override
  Object? handle(StateError error, ExecutionContext context) => 'handled';
}

void main() {
  group('ExecutionContext', () {
    test('exposes the HTTP view, header and body', () async {
      final request = requestFor(
        'POST',
        '/users/7',
        headers: {'X-Token': 'abc'},
        body: '{"a":1}',
      );
      final context = contextFor(request, pathParameters: {'id': '7'});

      expect(context.switchToHttp().request, same(request));
      expect(context.switchToHttp().pathParameters, {'id': '7'});
      expect(context.header('x-token'), 'abc');
      expect(context.header('missing'), isNull);
      expect(await context.body.json(), {'a': 1});
    });

    test('route metadata overrides controller metadata', () {
      final context = contextFor(
        requestFor('GET', '/'),
        metadata: [
          const Roles(['admin']),
          const Public(),
          const Roles(['user']),
        ],
      );

      expect(context.metadata<Roles>()?.names, ['admin']);
      expect(context.metadata<Public>(), isNotNull);
      expect(context.metadata<String>(), isNull);
    });

    test('items carry data from guards to handlers', () {
      final context = contextFor(requestFor('GET', '/'));
      context.items[#user] = 'ann';

      expect(context.items[#user], 'ann');
    });
  });

  group('pipeline contracts', () {
    test('Use resolves the component from the injector', () async {
      final container = await Container.create(
        Module(id: 'app', providers: [Provider((i) => AllowAll())]),
      );

      const use = Use<AllowAll>();

      expect(use.type, AllowAll);
      expect(use.resolve(container.root), same(container.root.get<AllowAll>()));
      expect(use.toString(), 'Use<AllowAll>');
    });

    test('ExceptionFilter catches only its type', () {
      const filter = StateErrorFilter();

      expect(filter.catches(StateError('x')), isTrue);
      expect(filter.catches(ArgumentError('x')), isFalse);
    });

    test('Enhancers.none is empty', () {
      expect(Enhancers.none.guards, isEmpty);
      expect(Enhancers.none.interceptors, isEmpty);
      expect(Enhancers.none.pipes, isEmpty);
      expect(Enhancers.none.filters, isEmpty);
    });
  });
}
