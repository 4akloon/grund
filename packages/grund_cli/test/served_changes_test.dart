import 'package:grund_cli/src/dev/served_changes.dart';
import 'package:test/test.dart';

void main() {
  group('ServedChanges.fromResponse', () {
    test('reads what the reassemble extension answers', () {
      final changes = ServedChanges.fromResponse({
        'applications': 1,
        'added': ['GET /tasks/:id', 7],
        'removed': ['DELETE /old'],
      });

      expect(changes.added, ['GET /tasks/:id', '7']);
      expect(changes.removed, ['DELETE /old']);
      expect(changes.count, 3);
    });

    test('an answer without the lists means nothing changed', () {
      for (final json in <Map<String, Object?>?>[
        null,
        <String, Object?>{},
        {'applications': 0},
        {'added': 'GET /x', 'removed': <Object?>[]},
      ]) {
        final changes = ServedChanges.fromResponse(json);

        expect(changes.count, 0, reason: '$json');
      }
    });
  });
}
