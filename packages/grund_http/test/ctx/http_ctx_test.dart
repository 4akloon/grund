import 'dart:convert';

import 'package:grund/grund.dart' show CancelSignal;
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/ctx_factory.dart';
import '../helpers/http_fixtures.dart';

final class NewUser {
  NewUser(this.name);

  factory NewUser.fromJson(Map<String, Object?> json) =>
      NewUser(json['name']! as String);

  final String name;
}

NewUser strictUser(Map<String, Object?> json) {
  if (json['name'] == '') throw const FormatException('name is empty');
  return NewUser.fromJson(json);
}

TypeMatcher<BadRequestException> problem(String code, String pointer) =>
    isA<BadRequestException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.pointer, 'pointer', pointer);

void main() {
  late CtxFactory contexts;

  setUpAll(() async => contexts = await CtxFactory.start());
  tearDownAll(() => contexts.close());

  group('HttpCtx parameters', () {
    test('reads path, query, header and cookie values', () {
      final c = contexts(
        requestFor(
          'GET',
          '/users/7?page=2&tag=a&tag=b',
          headers: {'x-api-key': 'k', 'cookie': 'sid=abc; theme="dark"'},
        ),
        pathParameters: {'id': '7'},
      );

      expect(c.path.integer('id'), 7);
      expect(c.query.integer('page'), 2);
      expect(c.query.all('tag'), ['a', 'b']);
      expect(c.headers.string('X-Api-Key'), 'k');
      expect(c.cookies.string('sid'), 'abc');
      expect(c.cookies.string('theme'), 'dark');
    });

    test('a query value is percent-decoded', () {
      final c = contexts(requestFor('GET', '/s?q=a%20b%2Fc'));

      expect(c.query.string('q'), 'a b/c');
    });

    test('an unknown path parameter is missing', () {
      final c = contexts(requestFor('GET', '/'));

      expect(
        () => c.path.integer('id'),
        throwsA(problem('parameter_missing', '/path/id')),
      );
    });

    test('the response head starts empty and the handler may change it', () {
      final c = contexts(requestFor('GET', '/'));

      expect(c.response.status, isNull);
      c.response.status = 201;
      expect(c.response.status, 201);
    });
  });

  group('HttpCtx call scope', () {
    test('values set on one context are not visible in another', () {
      final first = contexts(requestFor('GET', '/'));
      final second = contexts(requestFor('GET', '/'));

      first.set<String>('mine');

      expect(first<String>(), 'mine');
      expect(() => second<String>(), throwsA(anything));
    });

    test('the cancel signal is passed through', () {
      final cancel = CancelSignal();

      expect(contexts(requestFor('GET', '/'), cancel: cancel).cancel, cancel);
    });
  });

  group('HttpCtx cookies', () {
    test('quoted, repeated and malformed pairs', () {
      final c = contexts(
        requestFor(
          'GET',
          '/',
          headers: {'cookie': 'a="x y"; b=1; b=2; junk; =v'},
        ),
      );

      expect(c.cookies.string('a'), 'x y');
      expect(c.cookies.all('b'), ['1', '2']);
      expect(c.cookies.all('junk'), isEmpty);
      expect(c.cookies.all(''), isEmpty);
    });
  });

  group('HttpCtx body (RF-3)', () {
    test('decodes a JSON object', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":"ann"}'));

      expect((await c.body(NewUser.fromJson)).name, 'ann');
    });

    test('the body can be read more than once', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":"ann"}'));

      await c.body(NewUser.fromJson);
      expect((await c.body(NewUser.fromJson)).name, 'ann');
      expect(utf8.decode(await c.bytes()), '{"name":"ann"}');
    });

    test('malformed JSON is a 400 body_invalid', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":'));

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('an empty body is a 400 body_invalid', () async {
      final c = contexts(requestFor('POST', '/'));

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('a JSON value that is not an object is a 400', () async {
      for (final body in ['[1]', '"x"', '3', 'null']) {
        final c = contexts(requestFor('POST', '/', body: body));

        await expectLater(
          c.body(NewUser.fromJson),
          throwsA(problem('body_invalid', '/body')),
          reason: body,
        );
      }
    });

    test('a missing required field is a 400, not a 500', () async {
      final c = contexts(requestFor('POST', '/', body: '{}'));

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('a field of the wrong type is a 400', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":5}'));

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('a FormatException from fromJson is a 400 with its message', () async {
      final c = contexts(requestFor('POST', '/', body: '{"name":""}'));

      await expectLater(
        c.body(strictUser),
        throwsA(
          problem(
            'body_invalid',
            '/body',
          ).having((e) => e.message, 'message', contains('name is empty')),
        ),
      );
    });

    test('any other failure of fromJson is not hidden', () async {
      final c = contexts(requestFor('POST', '/', body: '{}'));

      await expectLater(
        c.body<NewUser>((_) => throw StateError('bug')),
        throwsStateError,
      );
    });

    test('bodyList builds every item and points at a bad one', () async {
      final ok = contexts(
        requestFor('POST', '/', body: '[{"name":"a"},{"name":"b"}]'),
      );
      final bad = contexts(
        requestFor('POST', '/', body: '[{"name":"a"},{"nope":1}]'),
      );
      final notArray = contexts(requestFor('POST', '/', body: '{}'));

      expect((await ok.bodyList(NewUser.fromJson)).map((u) => u.name), [
        'a',
        'b',
      ]);
      await expectLater(
        bad.bodyList(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body/1')),
      );
      await expectLater(
        notArray.bodyList(NewUser.fromJson),
        throwsA(problem('body_invalid', '/body')),
      );
    });

    test('a declared size over the limit is a 413 without reading', () async {
      var read = false;
      final request = HttpRequest(
        method: 'POST',
        uri: Uri.parse('/'),
        headers: HeaderMap.of({'content-length': '2000'}),
        body: RequestBody(
          Stream.fromIterable([utf8.encode('x')]).map((chunk) {
            read = true;
            return chunk;
          }),
        ),
      );
      final c = contexts(request, maxBodyBytes: 1000);

      await expectLater(
        c.bytes(),
        throwsA(
          isA<PayloadTooLargeException>()
              .having((e) => e.status, 'status', 413)
              .having((e) => e.code, 'code', 'body_too_large'),
        ),
      );
      expect(read, isFalse);
    });

    test('a streamed body over the limit is a 413 while reading', () async {
      final request = HttpRequest(
        method: 'POST',
        uri: Uri.parse('/'),
        body: RequestBody(
          Stream.fromIterable([List.filled(600, 120), List.filled(600, 120)]),
        ),
      );
      final c = contexts(request, maxBodyBytes: 1000);

      await expectLater(
        c.body(NewUser.fromJson),
        throwsA(isA<PayloadTooLargeException>()),
      );
    });

    test('a body exactly at the limit is accepted', () async {
      final c = contexts(
        requestFor('POST', '/', body: '{"name":"ann"}'),
        maxBodyBytes: '{"name":"ann"}'.length,
      );

      expect((await c.body(NewUser.fromJson)).name, 'ann');
    });
  });

  group('HttpCtx form', () {
    test(
      'reads the fields of a form body with the parameter readers',
      () async {
        final c = contexts(requestFor('POST', '/', body: 'name=ann&age=7'));

        final form = await c.form();

        expect(form.string('name'), 'ann');
        expect(form.integer('age'), 7);
      },
    );

    test('a missing field points at /body/<name>', () async {
      final c = contexts(requestFor('POST', '/', body: 'name=ann'));
      final form = await c.form();

      expect(
        () => form.string('password'),
        throwsA(problem('parameter_missing', '/body/password')),
      );
    });

    test('a missing field is labelled as a form field', () async {
      final c = contexts(requestFor('POST', '/', body: 'name=ann'));
      final form = await c.form();

      expect(
        () => form.string('password'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.message,
            'message',
            'Missing form field "password".',
          ),
        ),
      );
    });

    test('an empty body has no fields', () async {
      final c = contexts(requestFor('POST', '/', body: ''));
      final form = await c.form();

      expect(form.all('name'), isEmpty);
      expect(form.stringOrNull('name'), isNull);
    });

    test(
      'a repeated field keeps every value, string reads the first',
      () async {
        final c = contexts(requestFor('POST', '/', body: 'tag=a&tag=b&tag=c'));
        final form = await c.form();

        expect(form.all('tag'), ['a', 'b', 'c']);
        expect(form.string('tag'), 'a');
      },
    );

    test('the content type is not checked: a JSON-typed body still parses '
        'as a form', () async {
      final c = contexts(
        requestFor(
          'POST',
          '/',
          body: 'name=ann',
          headers: {'content-type': 'application/json'},
        ),
      );

      expect((await c.form()).string('name'), 'ann');
    });

    test('a bad escape is a 400 body_invalid', () async {
      final c = contexts(requestFor('POST', '/', body: 'name=%zz'));

      await expectLater(c.form(), throwsA(problem('body_invalid', '/body')));
    });

    test('a body that is not UTF-8 is a 400 body_invalid', () async {
      final c = contexts(
        HttpRequest(
          method: 'POST',
          uri: Uri.parse('/'),
          body: RequestBody.bytes([0x6e, 0x3d, 0xff]),
        ),
      );

      await expectLater(c.form(), throwsA(problem('body_invalid', '/body')));
    });

    test('a form over the limit is a 413', () async {
      final c = contexts(
        requestFor('POST', '/', body: 'name=${'x' * 20}'),
        maxBodyBytes: 10,
      );

      await expectLater(c.form(), throwsA(isA<PayloadTooLargeException>()));
    });
  });
}
