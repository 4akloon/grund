import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  final logger = Logger('grund.test');
  late Level rootLevel;

  setUp(() => rootLevel = Logger.root.level);
  tearDown(() => Logger.root.level = rootLevel);

  test('console output writes formatted lines to the sink', () async {
    final lines = <String>[];
    final subscription = LogOutput.console(sink: lines.add).attach();

    logger.info('hello');
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(lines, hasLength(1));
    expect(lines.single, endsWith('[grund.test] hello'));
  });

  test('json output writes one parsable object per record', () async {
    final lines = <String>[];
    final subscription = LogOutput.json(sink: lines.add).attach();

    logger.info('hello');
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(
      (jsonDecode(lines.single) as Map<String, Object?>)['message'],
      'hello',
    );
  });

  test('records below the level are dropped', () async {
    final lines = <String>[];
    final subscription = LogOutput.console(
      level: Level.WARNING,
      sink: lines.add,
    ).attach();

    logger
      ..info('quiet')
      ..warning('loud');
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(lines.single, endsWith('loud'));
  });

  test('cancel stops the output and restores the root level', () async {
    Logger.root.level = Level.SEVERE;
    final lines = <String>[];
    final subscription = LogOutput.console(sink: lines.add).attach();
    expect(Logger.root.level, Level.INFO);

    await subscription.cancel();
    Logger.root.level = Level.ALL;
    logger.info('after');
    await Future<void>.delayed(Duration.zero);

    expect(lines, isEmpty);
    expect(Logger.root.level, Level.ALL);
  });

  test('cancel restores the level that attach replaced', () async {
    Logger.root.level = Level.SEVERE;
    final subscription = const LogOutput.console().attach();

    await subscription.cancel();

    expect(Logger.root.level, Level.SEVERE);
  });

  test('a second cancel leaves the root level alone', () async {
    Logger.root.level = Level.SEVERE;
    final subscription = const LogOutput.console().attach();
    await subscription.cancel();
    Logger.root.level = Level.FINE;

    await subscription.cancel();

    expect(Logger.root.level, Level.FINE);
  });

  test('none attaches nothing', () async {
    Logger.root.level = Level.SEVERE;
    final subscription = const LogOutput.none().attach();

    expect(Logger.root.level, Level.SEVERE);
    expect(Logger.root.onRecord.isBroadcast, isTrue);
    await subscription.cancel();
  });
}
