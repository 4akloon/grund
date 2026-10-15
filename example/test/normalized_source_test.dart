import 'package:test/test.dart';

import 'helpers/normalized_source.dart';

void main() {
  test('the same code laid out differently is equal once normalised', () {
    const compact = 'void f() { run(() { work(); }); }\n';
    const spread =
        'void f() {\n  run(\n    () {\n      work();\n    },\n  );\n}\n';

    expect(NormalizedSource.of(compact), NormalizedSource.of(spread));
  });

  test('a change of content stays a difference', () {
    const before = 'void f() { run(() { work(); }); }\n';
    const after = 'void f() { run(() { rest(); }); }\n';

    expect(NormalizedSource.of(before), isNot(NormalizedSource.of(after)));
  });
}
