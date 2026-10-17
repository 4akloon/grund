import 'package:grund/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/pages_app.dart';
import 'helpers/validation_sites.dart';

/// Matches [T], whether the start failure wraps it or not.
Matcher _declaration<T extends Object>() =>
    predicate<Object>((error) => error is T || '$error'.contains('$T'), 'a $T');

Future<TestApp> _startAt(String path, {JasprConfig? config}) =>
    StartedPagesApp.start([
      JasprModule(config: config ?? const JasprConfig()),
      SiteWithPagesModule<PathSite>((i) => PathSite(i, path)),
    ]);

void main() {
  group('site path validation', () {
    for (final path in ['/admin/', 'admin', '/', '/:x', '/a/*', '//a']) {
      test('"$path" is an InvalidSitePathError', () {
        expect(_startAt(path), throwsA(_declaration<InvalidSitePathError>()));
      });
    }

    test('a site path equal to a rootFiles entry is rejected', () {
      expect(
        _startAt(
          '/robots.txt',
          config: const JasprConfig(rootFiles: ['robots.txt']),
        ),
        throwsA(_declaration<InvalidSitePathError>()),
      );
    });

    test('a guarded site with a trailing slash cannot hide a page', () {
      expect(
        StartedPagesApp.start([
          const JasprModule(),
          publicSite(extra: ['/admin/x']),
          SiteWithPagesModule<PathSite>((i) => PathSite(i, '/admin/')),
        ]),
        throwsA(_declaration<InvalidSitePathError>()),
      );
    });

    test('a normalised site path starts', () async {
      final app = await _startAt('/admin');
      expect(app, isNotNull);
    });
  });
}
