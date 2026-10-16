import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/src/jaspr_request.dart';
import 'package:test/test.dart';

HttpRequest _request(String target, {HeaderMap? headers}) => HttpRequest(
  method: 'GET',
  uri: Uri.parse(target),
  headers: headers ?? HeaderMap(),
);

void main() {
  test('the path and the query reach Jaspr as they were sent', () {
    final request = JasprRequest.from(_request('/a/b?x=1&y=%20z'));

    expect(request.method, 'GET');
    expect(request.url.path, 'a/b');
    expect(request.requestedUri.path, '/a/b');
    expect(request.requestedUri.query, 'x=1&y=%20z');
    expect(request.handlerPath, '/');
  });

  test('an empty path is the root', () {
    final request = JasprRequest.from(_request(''));

    expect(request.requestedUri.path, '/');
    expect(request.requestedUri.hasQuery, isFalse);
  });

  test('every value of a header is passed', () {
    final headers = HeaderMap()
      ..add('accept', 'text/html')
      ..add('x-many', 'a')
      ..add('x-many', 'b');

    final request = JasprRequest.from(_request('/', headers: headers));

    expect(request.headersAll['x-many'], ['a', 'b']);
    expect(request.headers['accept'], 'text/html');
  });
}
