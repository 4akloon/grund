import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/jaspr_setup.dart';
import 'package:grund_jaspr/src/page/page_renderer.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

import 'helpers/no_injector.dart';
import 'helpers/pages_app.dart';

final class _Site extends PageSite {
  _Site() : super(const NoInjector());
}

final class _MatchReader extends StatelessComponent {
  const _MatchReader();

  @override
  Component build(BuildContext context) =>
      Component.text('slug ${context.pageMatch?.params['slug']}');
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

final class _RenderApi extends HttpApi {
  _RenderApi(super.injector);

  static const _renderer = PageRenderer();

  @override
  List<Route> get routes => [
    Route.get(
      '/status',
      (c) => _renderer.render(c, const Component.text('hi'), status: 404),
    ),
    Route.get(
      '/match',
      (c) => _renderer.render(c, const _MatchReader(), match: _match),
    ),
    Route.get(
      '/own-status',
      (c) => _renderer.render(c, const _OwnStatus(), status: 404),
    ),
    Route.get('/plain', (c) => _renderer.render(c, const _MatchReader())),
    Route.get('/throws', (c) async {
      try {
        return await _renderer.render(c, const _Thrower());
      } on PageRenderError {
        return 'render-error';
      }
    }),
  ];

  static final _match = PageMatch(
    page: SitePage(
      site: _Site(),
      page: Page('/:slug', build: (_) => const Component.text('x')),
      path: '/:slug',
    ),
    params: const {'slug': 'a'},
  );
}

final class _RenderModule extends Module {
  const _RenderModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<_RenderApi>(_RenderApi.new, dependsOn: const []),
  ];
}

void main() {
  setUpAll(JasprSetup.ensureInitialized);

  test('render uses the given status and renders the component', () async {
    final client = await PagesApp.start([const _RenderModule()]);

    final response = await client.get('/status');

    expect(response.status, 404);
    expect(response.text, contains('hi'));
  });

  test('a status the component set itself wins over status', () async {
    final client = await PagesApp.start([const _RenderModule()]);

    final response = await client.get('/own-status');

    expect(response.status, 203);
  });

  test('a component sees the match through context.pageMatch', () async {
    final client = await PagesApp.start([const _RenderModule()]);

    final response = await client.get('/match');

    expect(response.text, contains('slug a'));
  });

  test('without a match context.pageMatch is null', () async {
    final client = await PagesApp.start([const _RenderModule()]);

    final response = await client.get('/plain');

    expect(response.text, contains('slug null'));
  });

  test('a component that throws gives PageRenderError', () async {
    final client = await PagesApp.start([const _RenderModule()]);

    final response = await client.get('/throws');

    expect(response.text, contains('render-error'));
  });
}
