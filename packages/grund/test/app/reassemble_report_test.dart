import 'package:grund/grund.dart';
import 'package:test/test.dart';

void main() {
  group('ReassembleReport', () {
    test('between lists what appeared and what disappeared, sorted', () {
      final report = ReassembleReport.between(
        ['GET /a', 'GET /b'],
        ['GET /d', 'GET /b', 'GET /c'],
      );

      expect(report.added, ['GET /c', 'GET /d']);
      expect(report.removed, ['GET /a']);
      expect(report.changed, 3);
    });

    test('merge joins two reports and keeps the lists sorted', () {
      final merged = const ReassembleReport(
        added: ['b'],
        removed: ['x'],
      ).merge(const ReassembleReport(added: ['a'], removed: ['w']));

      expect(merged.added, ['a', 'b']);
      expect(merged.removed, ['w', 'x']);
    });

    test('toJson uses the keys the dev client reads', () {
      expect(const ReassembleReport(added: ['a']).toJson(), {
        'added': ['a'],
        'removed': <String>[],
      });
    });
  });
}
