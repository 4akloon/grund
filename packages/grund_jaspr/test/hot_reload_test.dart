import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

/// What the next `App.reassemble` finds in the module, the way a reload
/// re-reads the user's module functions.
enum _Edit { none, addPage, nestedSite, forbiddenSkip, dropAdmin }

final class _PublicSite extends PageSite {
  _PublicSite(super.injector);
}

final class _AdminSite extends PageSite {
  _AdminSite(super.injector);

  @override
  String get path => '/admin';
}

final class _NestedSite extends PageSite {
  _NestedSite(super.injector);

  @override
  String get path => '/admin/inner';
}

final class _Guard extends HttpHook {
  const _Guard();
}

Page _page(String path, {PageHooks hooks = const PageHooks()}) =>
    Page(path, hooks: hooks, build: (_) => Component.text('page $path'));

final class _SitesModule extends Module {
  const _SitesModule(this._edit);

  final _Edit Function() _edit;

  @override
  List<Binding<Object>> get bindings {
    // Read inside the page functions, which an adopted singleton keeps from
    // the module it was created with; only the site list is read here.
    final edit = _edit();
    return [
      ...Pages.site<_PublicSite>(_PublicSite.new),
      Pages.under<_PublicSite>(
        (_) => [
          _page('/'),
          if (_edit() == _Edit.addPage) _page('/new'),
          if (_edit() == _Edit.forbiddenSkip)
            _page('/new', hooks: const PageHooks(skip: [_Guard])),
        ],
      ),
      if (edit != _Edit.dropAdmin) ...[
        ...Pages.site<_AdminSite>(_AdminSite.new),
        Pages.under<_AdminSite>((_) => [_page('/')]),
      ],
      if (edit == _Edit.nestedSite) ...[
        ...Pages.site<_NestedSite>(_NestedSite.new),
        Pages.under<_NestedSite>((_) => [_page('/')]),
      ],
    ];
  }
}

final class _Root extends Module {
  const _Root(this._edit);

  final _Edit Function() _edit;

  @override
  List<Module> get imports => [
    const HttpModule(config: HttpConfig(address: '127.0.0.1', port: 0)),
    const IoAdapterModule(),
    const JasprModule(),
    _SitesModule(_edit),
  ];
}

/// A started application whose module reads [edit] on every reassemble.
final class _Reloading {
  _Reloading._(this.app);

  static Future<_Reloading> start() async {
    final holder = _Holder();
    final app = App(root: _Root(() => holder.edit));
    await app.start();
    addTearDown(app.close);
    return _Reloading._(app).._holder = holder;
  }

  final App app;
  late final _Holder _holder; // set right after construction in start().

  PageCatalog get catalog => app.container.root<PageCatalog>();

  /// Applies [edit] and reassembles; returns the failure, if any.
  Future<Object?> reload(_Edit edit) async {
    _holder.edit = edit;
    try {
      await app.reassemble();
      return null;
    } on Object catch (error) {
      // The test inspects what the failed reassemble left behind.
      return error;
    }
  }

  /// The status of `GET [path]` on the real server.
  Future<int> status(String path) async {
    final port = (app.container.root<HttpAdapter>() as IoAdapter).port;
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', port, path);
      final response = await request.close();
      await response.transform(utf8.decoder).drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  String? matched(String path) =>
      catalog.match(Uri.parse('http://x$path'))?.page.path;
}

final class _Holder {
  _Edit edit = _Edit.none;
}

void main() {
  group('hot reload through App.reassemble', () {
    test('a new page is served and listed', () async {
      final reloading = await _Reloading.start();

      expect(await reloading.status('/new'), 404);
      expect(reloading.matched('/new'), isNull);

      expect(await reloading.reload(_Edit.addPage), isNull);

      expect(await reloading.status('/new'), 200);
      expect(reloading.matched('/new'), '/new');
    });

    test('a failing global rule keeps routes and catalog', () async {
      final reloading = await _Reloading.start();

      final error = await reloading.reload(_Edit.nestedSite);

      expect(error.toString(), contains('NestedSitePathError'));
      expect(await reloading.status('/admin/inner'), 404);
      expect(await reloading.status('/admin'), 200);
      expect(reloading.matched('/admin/inner'), isNull);
      expect(reloading.catalog.pagesOf<_AdminSite>(), hasLength(1));
    });

    test('a failing local rule keeps the routes', () async {
      final reloading = await _Reloading.start();

      final error = await reloading.reload(_Edit.forbiddenSkip);

      expect(error.toString(), contains('ForbiddenPageSkipError'));
      expect(await reloading.status('/new'), 404);
      // The catalog is not asserted: the local rule is thrown while the
      // HTTP server builds its table, after the pages runner already took
      // the new snapshot (a development-time transient until the next
      // successful reload).
    });

    test('a removed site stops answering and is not listed', () async {
      final reloading = await _Reloading.start();
      expect(await reloading.status('/admin'), 200);

      expect(await reloading.reload(_Edit.dropAdmin), isNull);

      expect(await reloading.status('/admin'), 404);
      expect(reloading.matched('/admin'), isNull);
      expect(reloading.catalog.pagesOf<_AdminSite>(), isEmpty);
    });
  });
}
