// Module entries the generator cannot read.
import 'package:grund_annotations/grund_annotations.dart';

import 'basic.dart';

/// Every list holds something wrong.
@Module(
  imports: [String, 'db'],
  providers: [
    42,
    dbUrl,
    Value(1, token: dbUrl),
  ],
  controllers: [Repo],
  exports: [3],
)
class BrokenModule {}
