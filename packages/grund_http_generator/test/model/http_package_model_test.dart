import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

void main() {
  test('an api makes the package non-empty', () {
    final package = PackageModel(
      packageName: 'app',
      languageVersion: Version(3, 8, 0),
      extensions: [
        HttpPackageModel(
          apis: [
            ApiModel(
              type: GraphModels.type('TasksApi'),
              path: '/tasks',
              location: const SourceLocation('lib/app.dart', 1, 7),
              libraryPath: 'lib/app.dart',
            ),
          ],
        ),
      ],
    );

    expect(package.isEmpty, isFalse);
  });
}
