import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:test/test.dart';

void main() {
  test('the http codes are unique and distinct from the core codes', () {
    final ids = [
      for (final code in DiagnosticCode.values) code.id,
      for (final code in HttpDiagnosticCodes.values) code.id,
    ];

    expect(ids.toSet(), hasLength(ids.length));
  });
}
