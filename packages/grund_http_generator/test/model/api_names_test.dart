import 'package:grund_http_generator/src/model/api_names.dart';
import 'package:test/test.dart';

void main() {
  test('the routes class derives from the api class name', () {
    expect(ApiNames.routes('TasksApi'), 'TasksApiRoutes');
  });
}
