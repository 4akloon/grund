import 'package:grund_auth/grund_auth.dart';
import 'package:test/test.dart';

final _start = DateTime.utc(2026, 10, 16, 12);

Session _session(String id, {Duration lasts = const Duration(hours: 1)}) =>
    Session(
      id: id,
      userId: 'ann',
      createdAt: _start,
      expiresAt: _start.add(lasts),
    );

void main() {
  // Both are assigned in setUp, which runs before every test.
  late DateTime now;
  late InMemorySessionStore store;

  setUp(() {
    now = _start;
    store = InMemorySessionStore(now: () => now);
  });

  test('reads a created session back', () async {
    final session = _session('a');
    await store.create(session);

    expect(await store.read('a'), same(session));
  });

  test('an unknown id reads as null', () async {
    expect(await store.read('nope'), isNull);
  });

  test('an expired session reads as null and is gone', () async {
    await store.create(_session('a'));
    now = _start.add(const Duration(hours: 1));

    expect(await store.read('a'), isNull);
    now = _start;
    expect(await store.read('a'), isNull);
  });

  test('a deleted session reads as null', () async {
    await store.create(_session('a'));
    await store.delete('a');

    expect(await store.read('a'), isNull);
  });

  test('create removes the expired sessions', () async {
    await store.create(_session('old', lasts: const Duration(minutes: 1)));
    now = _start.add(const Duration(minutes: 2));
    await store.create(_session('new', lasts: const Duration(hours: 2)));
    now = _start;

    expect(await store.read('old'), isNull);
  });

  test('create keeps the live sessions', () async {
    await store.create(_session('live', lasts: const Duration(hours: 2)));
    await store.create(_session('other'));

    expect(await store.read('live'), isNotNull);
  });

  test('create with an existing id replaces the session', () async {
    await store.create(_session('a'));
    final replacement = Session(
      id: 'a',
      userId: 'bob',
      createdAt: _start,
      expiresAt: _start.add(const Duration(hours: 1)),
    );
    await store.create(replacement);

    expect(await store.read('a'), same(replacement));
  });
}
