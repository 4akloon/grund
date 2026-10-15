import 'package:grund_generator/src/emit/library_writer.dart';
import 'package:test/test.dart';

void main() {
  test('validPackageName accepts lowercase names with digits and _', () {
    for (final name in ['app', 'app_1', '_app', 'a']) {
      expect(
        LibraryWriter.validPackageName.hasMatch(name),
        isTrue,
        reason: name,
      );
    }
  });

  test('validPackageName rejects capitals, leading digits and dashes', () {
    for (final name in ['App', '1app', 'my-app', '', 'app.x']) {
      expect(
        LibraryWriter.validPackageName.hasMatch(name),
        isFalse,
        reason: name,
      );
    }
  });
}
