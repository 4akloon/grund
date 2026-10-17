import 'package:grund/grund.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

final class _NoInjector implements Injector {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final injector = _NoInjector();
  const e1 = SitemapEntry(params: {'slug': 'a'});
  const e2 = SitemapEntry(params: {'slug': 'b'});
  const e3 = SitemapEntry(params: {'slug': 'c'});

  group('SitemapEntries.all', () {
    final entries = SitemapEntries.all((_) async => [e1, e2, e3]);

    test('counts the list', () async {
      expect(await entries.count(injector), 3);
    });

    test('slices the list', () async {
      expect(await entries.slice(injector, 1, 1), [e2]);
      expect(await entries.slice(injector, 2, 10), [e3]);
      expect(await entries.slice(injector, 5, 10), isEmpty);
    });
  });

  group('SitemapEntries.paged', () {
    test('passes offset and limit and counts once per call', () async {
      var counts = 0;
      final loads = <(int, int)>[];
      final entries = SitemapEntries.paged(
        count: (_) async => ++counts,
        load: (_, offset, limit) async {
          loads.add((offset, limit));
          return [e1];
        },
      );
      expect(await entries.count(injector), 1);
      expect(await entries.slice(injector, 4, 2), [e1]);
      expect(await entries.count(injector), 2);
      expect(loads, [(4, 2)]);
    });
  });
}
