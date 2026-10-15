// Module entries the generator cannot read.
import 'package:grund_annotations/grund_annotations.dart';

import 'basic.dart';

/// Every list holds something wrong.
@Module(imports: [String, 'db'], providers: [42, Label()], exports: [3])
class BrokenModule {}

/// Not a Module.
final class Label {
  /// Creates it.
  const Label();
}

/// Uses the same names so the file is reachable from the tests.
const brokenUses = DbModule();
