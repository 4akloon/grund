import 'package:grund/src/di/key.dart';
import 'package:test/test.dart';

class _Repo {}

void main() {
  group('Key', () {
    test('equals a key with the same type and name', () {
      expect(const Key<_Repo>(), const Key<_Repo>());
      expect(const Key<_Repo>('a'), const Key<_Repo>('a'));
      expect(const Key<_Repo>().hashCode, const Key<_Repo>().hashCode);
      expect(const Key<_Repo>('a').hashCode, const Key<_Repo>('a').hashCode);
    });

    test('differs by type', () {
      expect(const Key<_Repo>(), isNot(const Key<String>()));
    });

    test('differs by name', () {
      expect(const Key<_Repo>('a'), isNot(const Key<_Repo>('b')));
      expect(const Key<_Repo>('a'), isNot(const Key<_Repo>()));
    });

    test('is usable as a map key', () {
      final map = {const Key<_Repo>('a'): 1};

      expect(map[const Key<_Repo>('a')], 1);
      expect(map[const Key<_Repo>()], isNull);
    });

    test('exposes its type as a value', () {
      expect(const Key<_Repo>().type, _Repo);
    });

    test('prints the type, and the name when there is one', () {
      expect(const Key<_Repo>().toString(), '_Repo');
      expect(const Key<_Repo>('primary').toString(), "_Repo('primary')");
    });
  });
}
