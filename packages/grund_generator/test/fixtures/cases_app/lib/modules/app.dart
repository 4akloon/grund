// A root module importing an annotated module and an explicit one.
import 'package:grund_annotations/grund_annotations.dart';

import 'basic.dart';
import 'explicit.dart';

/// The root.
@Module(imports: [DbModule, explicitModule], exports: [DbModule])
class AppModule {}
