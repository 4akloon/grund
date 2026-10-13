import 'dart:convert';
import 'dart:typed_data';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/pipeline/response_serializer.dart';
import 'package:test/test.dart';

final class User {
  User(this.name);
  final String name;
  Map<String, Object?> toJson() => {'name': name};
}

final class Money {
  Money(this.cents);
  final int cents;
}

final class Opaque {}

final class Broken {
  Object? toJson() => throw StateError('no json');
}

Future<String> text(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

HttpResponse serialize(
  Object? result, {
  ResponseHead? head,
  SerializerRegistry? registry,
}) => ResponseSerializer(
  registry ?? SerializerRegistry(),
).serialize(result, head ?? ResponseHead());

void main() {
  group('ResponseSerializer', () {
    test('null is 204 without a body', () async {
      final response = serialize(null);

      expect(response.status, 204);
      expect(response.headers['content-type'], isNull);
      expect(await response.body.readAll(), isEmpty);
    });

    test('String is text/plain', () async {
      final response = serialize('hi');

      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(await text(response), 'hi');
    });

    test('Uint8List and byte streams are octet-stream', () async {
      final bytes = serialize(Uint8List.fromList([1, 2]));
      final streamed = serialize(Stream.value(const [3, 4]));

      expect(bytes.headers['content-type'], 'application/octet-stream');
      expect(await bytes.body.readAll(), [1, 2]);
      expect(streamed.body, isA<StreamBody>());
      expect(await streamed.body.readAll(), [3, 4]);
    });

    test('maps, lists, scalars and toJson objects are JSON', () async {
      final response = serialize({
        'users': [User('ann')],
        'n': 1,
        'ok': true,
      });

      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(
        await text(response),
        '{"users":[{"name":"ann"}],"n":1,"ok":true}',
      );
      expect(await text(serialize(42)), '42');
    });

    // A list of ints is data the client asked for as JSON, not raw bytes.
    test('List<int> is a JSON array, not a byte body', () async {
      final response = serialize(<int>[1, 2, 3]);

      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(await text(response), '[1,2,3]');
    });

    test('HttpResponse passes through and keeps its own headers', () {
      final head = ResponseHead()
        ..status = 201
        ..headers.set('x-trace', '7')
        ..headers.set('content-type', 'text/html');
      final original = HttpResponse.text('x', status: 202);

      final response = serialize(original, head: head);

      expect(response.status, 202);
      expect(response.headers['x-trace'], '7');
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
    });

    test('head status and headers override the defaults', () {
      final head = ResponseHead()
        ..status = 201
        ..headers.set('content-type', 'text/html; charset=utf-8')
        ..headers.set('location', '/users/1');

      final response = serialize('<b>made</b>', head: head);

      expect(response.status, 201);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(response.headers['location'], '/users/1');
    });

    test('registered serializers handle types without toJson', () async {
      final registry = SerializerRegistry()
        ..register<Money>((m) => {'cents': m.cents});

      final response = serialize({
        'price': Money(150),
        'history': [Money(1)],
      }, registry: registry);

      expect(
        await text(response),
        '{"price":{"cents":150},"history":[{"cents":1}]}',
      );
    });

    test('a throwing toJson is a SerializationError with its cause', () {
      expect(
        () => serialize(Broken()),
        throwsA(
          isA<SerializationError>()
              .having((e) => e.valueType, 'type', Broken)
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
    });

    test('an unencodable value is a SerializationError', () {
      expect(
        () => serialize({'x': Opaque()}),
        throwsA(
          isA<SerializationError>()
              .having((e) => e.valueType, 'type', Opaque)
              .having(
                (e) => e.message,
                'message',
                contains('register<Opaque>'),
              ),
        ),
      );
    });
  });
}
