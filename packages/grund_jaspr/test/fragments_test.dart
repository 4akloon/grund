import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/jaspr_setup.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/pages_app.dart';

final class _Greeter {
  String get word => 'hello';
}

final class _Fragment extends StatelessComponent {
  const _Fragment();

  @override
  Component build(BuildContext context) =>
      p([Component.text('item ${context.call<_Greeter>().word}')]);
}

final class _CookieFragment extends StatelessComponent {
  const _CookieFragment();

  @override
  Component build(BuildContext context) {
    context.setCookie('f', '1');
    return const Component.text('cookie');
  }
}

final class _OwnStatus extends StatelessComponent {
  const _OwnStatus();

  @override
  Component build(BuildContext context) {
    context.setStatusCode(203);
    return const Component.text('own');
  }
}

final class _Thrower extends StatelessComponent {
  const _Thrower();

  @override
  Component build(BuildContext context) => throw StateError('boom');
}

final class _FragmentApi extends HttpApi {
  _FragmentApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/frag', (c) => Fragments.respond(c, const _Fragment())),
    Route.get(
      '/created',
      (c) => Fragments.respond(c, const _Fragment(), status: 201),
    ),
    Route.get(
      '/own-status',
      (c) => Fragments.respond(c, const _OwnStatus(), status: 201),
    ),
    Route.get('/cookie', (c) => Fragments.respond(c, const _CookieFragment())),
    Route.get('/throws', (c) async {
      try {
        return await Fragments.respond(c, const _Thrower());
      } on PageRenderError {
        return 'render-error';
      }
    }),
  ];
}

final class _FragmentModule extends Module {
  const _FragmentModule();

  @override
  List<Module> get imports => const [JasprModule()];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<_Greeter>((_) => _Greeter(), dependsOn: const []),
    Singleton<_FragmentApi>(_FragmentApi.new, dependsOn: const []),
  ];
}

final class _NoJasprApi extends HttpApi {
  _NoJasprApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/frag', (c) async {
      try {
        return await Fragments.respond(c, const _Fragment());
      } on JasprSetupError catch (e) {
        return e.reason;
      }
    }),
  ];
}

final class _NoJasprModule extends Module {
  const _NoJasprModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<_NoJasprApi>(_NoJasprApi.new, dependsOn: const []),
  ];
}

void main() {
  setUpAll(JasprSetup.ensureInitialized);

  test('the body is the component without a document', () async {
    final client = await PagesApp.start([const _FragmentModule()]);

    final response = await client.get('/frag');

    expect(response.text, contains('<p>item hello</p>'));
    for (final document in ['<html', '<head', '<body', '<!DOCTYPE']) {
      expect(response.text, isNot(contains(document)));
    }
  });

  test('headers: html, private no-cache, component cookie kept', () async {
    final client = await PagesApp.start([const _FragmentModule()]);

    final fragment = await client.get('/frag');
    final cookie = await client.get('/cookie');

    expect(fragment.headers['content-type'], 'text/html; charset=utf-8');
    expect(fragment.headers['cache-control'], 'private, no-cache');
    expect(cookie.headers['set-cookie'], contains('f=1'));
  });

  test('the status is 200 by default and the given one otherwise', () async {
    final client = await PagesApp.start([const _FragmentModule()]);

    expect((await client.get('/frag')).status, 200);
    expect((await client.get('/created')).status, 201);
  });

  test('a status the component set itself wins', () async {
    final client = await PagesApp.start([const _FragmentModule()]);

    expect((await client.get('/own-status')).status, 203);
  });

  test('a component that throws gives PageRenderError', () async {
    final client = await PagesApp.start([const _FragmentModule()]);

    expect((await client.get('/throws')).text, contains('render-error'));
  });

  test('a fragment gets no live reload script', () async {
    final client = await PagesApp.start([const _FragmentModule()]);
    final withReload = await PagesApp.start([const _LiveReloadModule()]);

    expect((await client.get('/frag')).text, isNot(contains('<script')));
    expect((await withReload.get('/frag')).text, isNot(contains('<script')));
  });

  test('without JasprModule the error names it', () async {
    final client = await PagesApp.start([const _NoJasprModule()]);

    final response = await client.get('/frag');

    expect(response.text, contains('JasprModule'));
  });
}

final class _LiveReloadModule extends Module {
  const _LiveReloadModule();

  @override
  List<Module> get imports => [
    JasprModule(
      config: JasprConfig(liveReloadUrl: Uri.parse('http://127.0.0.1:9/')),
    ),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<_Greeter>((_) => _Greeter(), dependsOn: const []),
    Singleton<_FragmentApi>(_FragmentApi.new, dependsOn: const []),
  ];
}
