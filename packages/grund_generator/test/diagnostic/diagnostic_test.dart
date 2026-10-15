import 'package:grund_generator/src/diagnostic/diagnostic.dart';
import 'package:grund_generator/src/diagnostic/diagnostic_code.dart';
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:test/test.dart';

Diagnostic _diagnostic({
  DiagnosticCode code = DiagnosticCode.missingProvider,
  SourceLocation location = const SourceLocation('lib/a.dart', 1, 2),
  String message = 'No provider.',
}) => Diagnostic(code, location, message);

void main() {
  test('diagnostics with the same code, location and message are equal', () {
    expect(_diagnostic(), _diagnostic());
    expect(_diagnostic().hashCode, _diagnostic().hashCode);
  });

  test('a different code, location or message makes them differ', () {
    expect(
      _diagnostic(code: DiagnosticCode.duplicateGeneratedName),
      isNot(_diagnostic()),
    );
    expect(
      _diagnostic(location: const SourceLocation('lib/a.dart', 1, 3)),
      isNot(_diagnostic()),
    );
    expect(_diagnostic(message: 'Other.'), isNot(_diagnostic()));
  });
}
