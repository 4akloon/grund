import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'helpers/pages_app.dart';
import 'helpers/sites.dart';

/// Sets the header `x-audit: on` on every response.
final class AuditHook extends HttpHook {
  const AuditHook();

  @override
  void before(HttpCtx c) => c.response.headers.set('x-audit', 'on');
}

class BaseGuard extends HttpHook {
  const BaseGuard();
}

final class ChildGuard extends BaseGuard {
  const ChildGuard();
}

/// A site under `/s` whose hooks and skippable types the test chooses.
final class ConfiguredSite extends PageSite {
  ConfiguredSite(super.injector);

  static List<HookRef<HttpHook>> hooks = const [];
  static List<Type> skippable = const [];

  @override
  String get path => '/s';

  @override
  List<HookRef<HttpHook>> get use => hooks;

  @override
  List<Type> get skippableHooks => skippable;
}

final class AuditedAdminSite extends PageSite {
  AuditedAdminSite(super.injector);

  @override
  String get path => '/admin';

  @override
  List<HookRef<HttpHook>> get use => const [
    HookRef<AdminGuard>.instance(AdminGuard()),
    HookRef<AuditHook>.instance(AuditHook()),
  ];

  @override
  List<Type> get skippableHooks => const [AdminGuard];
}

final class SiteModule<S extends PageSite> extends Module {
  const SiteModule(this.create, this.pages);

  final S Function(Injector) create;
  final List<Page> pages;

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<S>(create),
    Pages.under<S>((_) => pages),
  ];
}

Page _home() => Page('/', build: (_) => const Component.text('Home'));

Future<TestClient> _startAdmin() => PagesApp.start([
  const JasprModule(),
  SiteModule<AuditedAdminSite>(AuditedAdminSite.new, [
    _home(),
    Page(
      '/login',
      build: (_) => const Component.text('Login'),
      hooks: const PageHooks(skip: [AdminGuard]),
    ),
    Page('/users', build: (_) => const Component.text('Users')),
  ]),
]);

Future<TestClient> _startConfigured({
  required List<HookRef<HttpHook>> hooks,
  required List<Type> skippable,
  required List<Type> skip,
}) {
  ConfiguredSite.hooks = hooks;
  ConfiguredSite.skippable = skippable;
  return PagesApp.start([
    const JasprModule(),
    SiteModule<ConfiguredSite>(ConfiguredSite.new, [
      _home(),
      Page(
        '/p',
        build: (_) => const Component.text('P'),
        hooks: PageHooks(skip: skip),
      ),
    ]),
  ]);
}

Matcher _causedBy<T extends Object>() => throwsA(
  predicate((Object error) {
    Object? current = error;
    while (current != null) {
      if (current is T) return true;
      current = switch (current) {
        RunnerError(:final error) => error,
        ProviderCreationError(:final error) => error,
        _ => null,
      };
    }
    return false;
  }, 'is or wraps $T'),
);

void main() {
  group('skip', () {
    test('a page skips one site hook and keeps the others', () async {
      final client = await _startAdmin();

      final response = await client.get('/admin/login');

      expect(response.status, 200);
      expect(response.headers['x-audit'], 'on');
    });

    test('a page that skips nothing keeps the guard', () async {
      final client = await _startAdmin();

      expect((await client.get('/admin/users')).status, 401);
    });

    test('the site fallback ignores skip', () async {
      final client = await _startAdmin();

      expect((await client.get('/admin/nope')).status, 401);
    });

    test('a type outside skippableHooks is a declaration error', () {
      expect(
        _startConfigured(
          hooks: const [HookRef<AuditHook>.instance(AuditHook())],
          skippable: const [],
          skip: const [AuditHook],
        ),
        _causedBy<ForbiddenPageSkipError>(),
      );
    });

    test('a base type of a site hook is unknown', () {
      expect(
        _startConfigured(
          hooks: const [HookRef<AuditHook>.instance(AuditHook())],
          skippable: const [HttpHook],
          skip: const [HttpHook],
        ),
        _causedBy<UnknownPageSkipError>(),
      );
    });

    test('a subtype is not skipped by its base type', () {
      expect(
        _startConfigured(
          hooks: const [HookRef<ChildGuard>.instance(ChildGuard())],
          skippable: const [BaseGuard],
          skip: const [BaseGuard],
        ),
        _causedBy<UnknownPageSkipError>(),
      );
    });

    test('a type that occurs twice in the site is ambiguous', () {
      expect(
        _startConfigured(
          hooks: const [
            HookRef<AdminGuard>.instance(AdminGuard()),
            HookRef<AdminGuard>.instance(AdminGuard()),
          ],
          skippable: const [AdminGuard],
          skip: const [AdminGuard],
        ),
        _causedBy<AmbiguousPageSkipError>(),
      );
    });

    test('the unknown error lists the hook types of the site', () async {
      Object? failure;
      try {
        await _startConfigured(
          hooks: const [HookRef<AuditHook>.instance(AuditHook())],
          skippable: const [AdminGuard],
          skip: const [AdminGuard],
        );
      } on Object catch (error) {
        failure = error;
      }

      expect(
        failure.toString(),
        allOf(contains('/s/p'), contains('AuditHook')),
      );
    });

    test('a skip is logged at INFO', () async {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final previous = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previous);

      await _startAdmin();

      final skips = records.where((r) => r.message.contains('skips'));
      expect(skips.map((r) => (r.level, r.message)), [
        (Level.INFO, 'page /admin/login skips AdminGuard (site /admin)'),
      ]);
    });

    test('a skip on a parameter page is logged at WARNING', () async {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final previous = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previous);

      await PagesApp.start([
        const JasprModule(),
        SiteModule<AuditedAdminSite>(AuditedAdminSite.new, [
          _home(),
          Page(
            '/users/:id',
            build: (_) => const Component.text('U'),
            hooks: const PageHooks(skip: [AdminGuard]),
          ),
        ]),
      ]);

      expect(
        records.where((r) => r.message.contains('skips')).map((r) => r.level),
        [Level.WARNING],
      );
    });
  });
}
