import 'package:grund/grund.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

enum Status { active, banned }

final class CreateUser {
  CreateUser(this.name);

  factory CreateUser.fromJson(Map<String, Object?> json) => switch (json) {
    {'name': final String name} => CreateUser(name),
    _ => throw const FormatException('"name" must be a string'),
  };

  final String name;
}

/// Records what it sees and upper-cases strings.
final class UpperPipe implements Pipe<Object?, Object?> {
  final List<String> seen = [];

  @override
  Object? transform(Object? value, ArgumentMeta meta) {
    seen.add('${meta.source.name}:${meta.name}:${meta.type}');
    return value is String ? value.toUpperCase() : value;
  }
}

/// Supplies a default for an absent value.
final class DefaultPipe implements Pipe<Object?, Object?> {
  const DefaultPipe(this.fallback);
  final Object fallback;

  @override
  Object? transform(Object? value, ArgumentMeta meta) => value ?? fallback;
}

/// A genuinely typed pipe: String in, int out.
final class LengthPipe implements Pipe<String, int> {
  const LengthPipe();

  @override
  int transform(String value, ArgumentMeta meta) => value.length;
}

/// Appends a suffix, so the order of pipes is observable.
final class AppendPipe implements Pipe<Object?, Object?> {
  const AppendPipe(this.suffix);
  final String suffix;

  @override
  Object? transform(Object? value, ArgumentMeta meta) => '$value$suffix';
}

/// Typed input that tolerates an absent (null) value.
final class OrZeroPipe implements Pipe<String?, int> {
  const OrZeroPipe();

  @override
  int transform(String? value, ArgumentMeta meta) => value?.length ?? 0;
}

ExecutionContext contextWithPipes(
  String target, {
  Map<String, String> pathParameters = const {},
  List<Pipe<Object?, Object?>> pipes = const [],
  String? body,
}) => ExecutionContext(
  transport: HttpContext(
    request: requestFor('POST', target, body: body),
    response: ResponseHead(),
    pathParameters: pathParameters,
  ),
  controllerType: Object,
  handlerName: 'UsersController.find',
  pipes: pipes,
);

Matcher badRequest(String messagePart) => throwsA(
  isA<BadRequestException>().having(
    (e) => e.message,
    'message',
    contains(messagePart),
  ),
);

void main() {
  group('param', () {
    test('converts built-in types', () async {
      final context = contextWithPipes(
        '/',
        pathParameters: {
          'i': '7',
          'd': '1.5',
          'n': '3',
          'b': 'true',
          't': '2026-10-13T10:00:00Z',
          's': 'x',
        },
      );

      expect(await context.param<int>('i'), 7);
      expect(await context.param<double>('d'), 1.5);
      expect(await context.param<num>('n'), 3);
      expect(await context.param<bool>('b'), isTrue);
      expect(
        await context.param<DateTime>('t'),
        DateTime.utc(2026, 10, 13, 10),
      );
      expect(await context.param<String>('s'), 'x');
      expect(await context.param<int?>('i'), 7);
    });

    test('unparsable value is a 400 naming the parameter', () async {
      final context = contextWithPipes('/', pathParameters: {'id': 'abc'});

      await expectLater(
        context.param<int>('id'),
        badRequest('Invalid path parameter "id": expected int, got "abc".'),
      );
      await expectLater(context.param<bool>('id'), badRequest('expected bool'));
    });

    test('bad double, DateTime and nullable values are 400', () async {
      final context = contextWithPipes('/', pathParameters: {'v': 'abc'});

      await expectLater(
        context.param<double>('v'),
        badRequest('expected double'),
      );
      await expectLater(
        context.param<DateTime>('v'),
        badRequest('expected DateTime'),
      );
      await expectLater(context.param<int?>('v'), badRequest('expected int?'));
    });

    test('unknown parameter name is a programming error', () async {
      final context = contextWithPipes('/', pathParameters: {'id': '1'});

      await expectLater(
        context.param<int>('idd'),
        throwsA(
          isA<UnknownRouteParameterError>()
              .having((e) => e.declared, 'declared', ['id'])
              .having((e) => e.handlerName, 'handler', 'UsersController.find'),
        ),
      );
    });

    test('type without built-in conversion needs a pipe', () async {
      final context = contextWithPipes('/', pathParameters: {'u': 'x'});

      await expectLater(
        context.param<Uri>('u'),
        throwsA(
          isA<UnsupportedConversionError>().having(
            (e) => e.message,
            'message',
            contains('add a Pipe that returns Uri'),
          ),
        ),
      );
    });
  });

  group('query', () {
    test('absent parameter: null when nullable, 400 otherwise', () async {
      final context = contextWithPipes('/users?page=2');

      expect(await context.query<int>('page'), 2);
      expect(await context.query<int?>('size'), isNull);
      await expectLater(
        context.query<int>('size'),
        badRequest('Missing query parameter "size".'),
      );
    });

    test('takes the first of repeated values', () async {
      final context = contextWithPipes('/?tag=a&tag=b');

      expect(await context.query<String>('tag'), 'a');
    });

    test('EnumPipe converts by name and rejects unknown names', () async {
      final context = contextWithPipes('/?status=banned&bad=x');
      const pipes = [EnumPipe(Status.values)];

      expect(
        await context.query<Status>('status', pipes: pipes),
        Status.banned,
      );
      expect(await context.query<Status?>('none', pipes: pipes), isNull);
      await expectLater(
        context.query<Status>('bad', pipes: pipes),
        badRequest('expected one of active, banned, got "x"'),
      );
    });
  });

  group('pipes', () {
    test('configured pipes run before call pipes, on the raw value', () async {
      final upper = UpperPipe();
      final context = contextWithPipes(
        '/?name=ann',
        pipes: [upper, const AppendPipe('-a')],
      );

      final name = await context.query<String>(
        'name',
        pipes: [const AppendPipe('-b')],
      );

      expect(name, 'ANN-a-b');
      expect(upper.seen, ['query:name:String']);
    });

    test(
      'app, controller, route then call pipes run in order on a path',
      () async {
        final context = contextWithPipes(
          '/',
          pathParameters: {'id': '1'},
          pipes: [const AppendPipe('-app'), const AppendPipe('-route')],
        );

        final id = await context.param<String>(
          'id',
          pipes: [const AppendPipe('-call')],
        );

        expect(id, '1-app-route-call');
      },
    );

    test(
      'configured pipes run in order before call pipes on a query',
      () async {
        final context = contextWithPipes(
          '/?q=x',
          pipes: [const AppendPipe('-app'), const AppendPipe('-route')],
        );

        final value = await context.query<String>(
          'q',
          pipes: [const AppendPipe('-call')],
        );

        expect(value, 'x-app-route-call');
      },
    );

    test('a typed Pipe<String, int> works on a path parameter', () async {
      final context = contextWithPipes('/', pathParameters: {'name': 'anna'});

      expect(await context.param<int>('name', pipes: [const LengthPipe()]), 4);
    });

    test('a Pipe<String?, int> receives null for an absent query', () async {
      final context = contextWithPipes('/');

      expect(await context.query<int>('n', pipes: [const OrZeroPipe()]), 0);
    });

    test('a pipe may supply a value for an absent parameter', () async {
      final context = contextWithPipes('/');

      expect(
        await context.query<int>('page', pipes: [const DefaultPipe('1')]),
        1,
      );
    });
  });

  // Review Focus 2: bad bodies are client errors, not server errors.
  group('bodyAs', () {
    test('decodes a JSON object', () async {
      final context = contextWithPipes('/', body: '{"name":"ann"}');

      final user = await context.bodyAs(CreateUser.fromJson);

      expect(user.name, 'ann');
    });

    test('malformed JSON is a 400', () async {
      final context = contextWithPipes('/', body: '{"name":');

      await expectLater(
        context.bodyAs(CreateUser.fromJson),
        badRequest('Request body is not valid JSON'),
      );
    });

    test('a JSON array where an object is expected is a 400', () async {
      final context = contextWithPipes('/', body: '[1,2]');

      await expectLater(
        context.bodyAs(CreateUser.fromJson),
        badRequest('Request body must be a JSON object.'),
      );
    });

    test('FormatException from fromJson is a 400', () async {
      final context = contextWithPipes('/', body: '{"name":1}');

      await expectLater(
        context.bodyAs(CreateUser.fromJson),
        badRequest('Invalid request body: "name" must be a string'),
      );
    });

    test('pipes see the decoded JSON before fromJson', () async {
      final upper = UpperPipe();
      final context = contextWithPipes(
        '/',
        body: '{"name":"ann"}',
        pipes: [upper],
      );

      await context.bodyAs(CreateUser.fromJson);

      expect(upper.seen, ['body:body:CreateUser']);
    });
  });
}
