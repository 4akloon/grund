import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

void main() {
  test('a syntax problem prints like a diagnostic with syntax_error', () {
    const problem = SyntaxProblem(
      SourceLocation('lib/src/clock.dart', 2, 9),
      "Expected to find ';'.",
    );

    expect(
      '$problem',
      "lib/src/clock.dart:2:9: error: Expected to find ';'. [syntax_error]",
    );
  });

  test('syntax problems sort by location, then by message', () {
    const later = SyntaxProblem(SourceLocation('lib/b.dart', 1, 1), 'A.');
    const second = SyntaxProblem(SourceLocation('lib/a.dart', 3, 5), 'B.');
    const first = SyntaxProblem(SourceLocation('lib/a.dart', 3, 5), 'A.');

    expect([later, second, first]..sort(), [first, second, later]);
  });
}
