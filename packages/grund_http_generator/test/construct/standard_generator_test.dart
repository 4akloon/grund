import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:test/test.dart';

void main() {
  test('the standard generator runs the module and the api constructs', () {
    expect(StandardGenerator.instance.constructs.map((c) => c.runtimeType), [
      ModuleConstruct,
      ApiConstruct,
    ]);
  });
}
