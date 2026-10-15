import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/key.dart';
import 'package:test/test.dart';

class _Clock {}

void main() {
  group('Binding', () {
    test('Singleton keeps its key, scope and declared dependencies', () {
      final binding = Singleton<_Clock>(
        (i) => _Clock(),
        name: 'utc',
        dependsOn: const [Key<String>()],
      );

      expect(binding.key, const Key<_Clock>('utc'));
      expect(binding.scope, BindingScope.singleton);
      expect(binding.dependsOn, const [Key<String>()]);
    });

    test('Singleton.factory does not declare its dependencies', () {
      final binding = Singleton<_Clock>.factory((i) => _Clock());

      expect(binding.dependsOn, isNull);
    });

    test('Scoped and Transient have their own scopes', () {
      final scoped = Scoped<_Clock>((i) => _Clock(), dependsOn: const []);
      final transient = Transient<_Clock>((i) => _Clock(), dependsOn: const []);

      expect(scoped.scope, BindingScope.scoped);
      expect(transient.scope, BindingScope.transient);
    });

    test('a missing type argument is inferred as Object and rejected', () {
      // In a `List<Binding<Object>>` Dart infers `Object` for the type
      // argument that was left out.
      expect(
        () => <Binding<Object>>[
          Singleton((i) => _Clock(), dependsOn: const []),
        ],
        throwsArgumentError,
      );
    });

    test('Singleton<Object> throws an ArgumentError naming the fix', () {
      expect(
        () => Singleton<Object>((i) => _Clock(), dependsOn: const []),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Singleton<Clock>(...)'),
          ),
        ),
      );
    });

    test('Scoped<Object> and Transient<Object> throw as well', () {
      expect(
        () => Scoped<Object>((i) => _Clock(), dependsOn: const []),
        throwsArgumentError,
      );
      expect(
        () => Transient<Object>((i) => _Clock(), dependsOn: const []),
        throwsArgumentError,
      );
    });
  });
}
