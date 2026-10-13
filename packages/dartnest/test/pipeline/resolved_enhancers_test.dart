import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/pipeline/resolved_enhancers.dart';
import 'package:test/test.dart';

final class AuthGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) => true;
}

final class Timing implements Interceptor {
  @override
  Object? intercept(ExecutionContext context, Next<Object?> next) => next();
}

final class TrimPipe implements Pipe<Object?, Object?> {
  const TrimPipe();

  @override
  Object? transform(Object? value, ArgumentMeta meta) =>
      value is String ? value.trim() : value;
}

final class AnyFilter extends ExceptionFilter<Object> {
  const AnyFilter(this.name);
  final String name;

  @override
  Object? handle(Object error, ExecutionContext context) => name;
}

void main() {
  test('resolve and chain return unmodifiable lists', () async {
    final container = await Container.create(Module(id: 'app'));
    final resolved = ResolvedEnhancers.resolve(
      Enhancers(guards: [AuthGuard()], filters: const [AnyFilter('a')]),
      container.root,
      owner: 'Application',
    );
    final chained = ResolvedEnhancers.chain([resolved, resolved]);

    for (final lists in [resolved, chained]) {
      expect(() => lists.guards.add(AuthGuard()), throwsUnsupportedError);
      expect(() => lists.interceptors.add(Timing()), throwsUnsupportedError);
      expect(() => lists.pipes.add(const TrimPipe()), throwsUnsupportedError);
      expect(
        () => lists.filters.add(const AnyFilter('b')),
        throwsUnsupportedError,
      );
    }
  });

  group('ResolvedEnhancers.resolve', () {
    test('resolves Use through the injector and keeps instances', () async {
      final container = await Container.create(
        Module(id: 'app', providers: [Provider((i) => AuthGuard())]),
      );
      final timing = Timing();

      final resolved = ResolvedEnhancers.resolve(
        Enhancers(
          guards: const [Use<AuthGuard>()],
          interceptors: [timing],
          pipes: const [TrimPipe()],
          filters: const [AnyFilter('a')],
        ),
        container.root,
        owner: 'Application',
      );

      expect(resolved.guards.single, same(container.root.get<AuthGuard>()));
      expect(resolved.interceptors.single, same(timing));
      expect(resolved.pipes.single, isA<TrimPipe>());
      expect(resolved.filters.single, isA<AnyFilter>());
    });

    test('a component of the wrong kind fails with its location', () async {
      final container = await Container.create(Module(id: 'app'));

      expect(
        () => ResolvedEnhancers.resolve(
          Enhancers(guards: [Timing()]),
          container.root,
          owner: 'UsersController',
        ),
        throwsA(
          isA<InvalidComponentError>()
              .having((e) => e.owner, 'owner', 'UsersController')
              .having((e) => e.slot, 'slot', 'guards')
              .having((e) => e.actualType, 'actual', Timing)
              .having((e) => e.expectedType, 'expected', Guard)
              .having(
                (e) => e.message,
                'message',
                'UsersController lists Timing in guards, but it is not a Guard.',
              ),
        ),
      );
    });

    test('Use of a missing provider fails with MissingProviderError', () async {
      final container = await Container.create(Module(id: 'users'));

      expect(
        () => ResolvedEnhancers.resolve(
          const Enhancers(guards: [Use<AuthGuard>()]),
          container.root,
          owner: 'UsersController',
        ),
        throwsA(
          isA<MissingProviderError>()
              .having((e) => e.key, 'key', AuthGuard)
              .having((e) => e.moduleId, 'module', 'users'),
        ),
      );
    });
  });

  group('ResolvedEnhancers.chain', () {
    test('outer to inner, filters reversed', () {
      final app = ResolvedEnhancers(
        pipes: const [TrimPipe()],
        filters: const [AnyFilter('app')],
      );
      final controller = ResolvedEnhancers(
        filters: const [AnyFilter('controller')],
      );
      final route = ResolvedEnhancers(
        pipes: const [TrimPipe()],
        filters: const [AnyFilter('route')],
      );

      final chained = ResolvedEnhancers.chain([app, controller, route]);

      expect(chained.pipes, hasLength(2));
      expect(chained.filters.map((f) => (f as AnyFilter).name), [
        'route',
        'controller',
        'app',
      ]);
    });
  });
}
