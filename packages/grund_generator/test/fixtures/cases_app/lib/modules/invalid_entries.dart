// Module entries the generator cannot read.
import 'package:grund/annotations.dart';

import 'basic.dart';

/// Every list holds something wrong; `Module()` is the annotation, not the
/// base class a module extends.
@Module(
  imports: [String, 'db', Module()],
  providers: [42, Label()],
  exports: [3],
)
class BrokenModule {}

/// Not a Module.
final class Label {
  /// Creates it.
  const Label();
}

/// Uses the same names so the file is reachable from the tests.
const brokenUses = DbModule();
