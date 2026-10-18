import 'package:grund_jaspr/client_components.dart';
import 'package:jaspr/jaspr.dart';
import 'package:test/test.dart';

import 'helpers/client_samples.dart';

const _counter = ClientComponent<Counter>(
  'counter',
  encode: Counter.toParams,
  decode: Counter.fromParams,
);

void main() {
  test('a constant list of tear-offs has no problems', () {
    const list = ClientComponents([_counter]);
    expect(list.problems, isEmpty);
  });

  test('a duplicate name is named', () {
    const list = ClientComponents([
      _counter,
      ClientComponent<Plain>('counter', decode: _plain),
    ]);
    expect(list.problems, [contains("'counter' is registered twice")]);
  });

  test('two entries for one type are named', () {
    const list = ClientComponents([
      _counter,
      ClientComponent<Counter>('other', decode: Counter.fromParams),
    ]);
    expect(list.problems, [
      allOf(contains("'other'"), contains('Counter'), contains("'counter'")),
    ]);
  });

  test('a type inferred as Component is named', () {
    const list = ClientComponents([
      ClientComponent<Component>('loose', decode: _plain),
    ]);
    expect(list.problems, [contains("'loose' has no explicit type")]);
  });

  test('unusable names are named, one line each', () {
    const list = ClientComponents([
      ClientComponent<Counter>('Bad Name', decode: Counter.fromParams),
      ClientComponent<Plain>('', decode: _plain),
      ClientComponent<_Third>('a/b', decode: _third),
    ]);
    expect(list.problems, [
      contains("'Bad Name'"),
      contains("''"),
      contains("'a/b'"),
    ]);
  });

  test('valid names are accepted', () {
    const list = ClientComponents([
      ClientComponent<Counter>('a', decode: Counter.fromParams),
      ClientComponent<Plain>('my-counter_2', decode: _plain),
    ]);
    expect(list.problems, isEmpty);
  });

  test('type is the real component type', () {
    expect(_counter.type, Counter);
  });

  test('withType through ClientComponent<Component> encodes and decodes', () {
    const list = ClientComponents([_counter]);
    final entry = list.components.first;
    final params = entry.withType(_encodeCounter);
    expect(params, {'start': 3, 'label': 'n'});
    final built = entry.withType(_decodeWith(params));
    expect(built, isA<Counter>().having((c) => c.start, 'start', 3));
  });
}

Map<String, Object?> _encodeCounter<C extends Component>(ClientEntry<C> e) =>
    e.encode!(const Counter(3, 'n') as C);

Component Function<C extends Component>(ClientEntry<C>) _decodeWith(
  Map<String, Object?> params,
) =>
    <C extends Component>(e) => e.decode(params);

Plain _plain(Map<String, Object?> _) => const Plain();

class _Third extends StatelessComponent {
  const _Third();

  @override
  Component build(BuildContext context) => const Component.text('third');
}

_Third _third(Map<String, Object?> _) => const _Third();
