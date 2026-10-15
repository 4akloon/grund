import 'package:grund_http/grund_http.dart';
import 'package:grund_http/src/hook/middleware_chain.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

final class Tag implements Middleware {
  Tag(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    log.add('in $name');
    final response = await next();
    log.add('out $name');
    return response.mergeHeaders(HeaderMap.of({'x-$name': 'yes'}));
  }
}

final class Stop implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async =>
      HttpResponse.text('stopped', status: 429);
}

void main() {
  final log = <String>[];

  setUp(log.clear);

  Future<HttpResponse> terminal() async {
    log.add('terminal');
    return HttpResponse.text('ok');
  }

  group('MiddlewareChain', () {
    test(
      'runs the first middleware outermost and wraps the response',
      () async {
        final response = await MiddlewareChain.run(
          [Tag('a', log), Tag('b', log)],
          requestFor('GET', '/'),
          terminal,
        );

        expect(log, ['in a', 'in b', 'terminal', 'out b', 'out a']);
        expect(response.headers['x-a'], 'yes');
        expect(response.headers['x-b'], 'yes');
      },
    );

    test('a middleware that does not call next short-circuits', () async {
      final response = await MiddlewareChain.run(
        [Stop(), Tag('a', log)],
        requestFor('GET', '/'),
        terminal,
      );

      expect(response.status, 429);
      expect(log, isEmpty);
    });

    test('no middleware calls the terminal directly', () async {
      final response = await MiddlewareChain.run(
        const [],
        requestFor('GET', '/'),
        terminal,
      );

      expect(response.status, 200);
      expect(log, ['terminal']);
    });
  });
}
