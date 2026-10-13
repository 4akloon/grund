// Provider entries that are almost valid.
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'basic.dart';

/// Not a class.
enum Mode { fast, slow }

/// A function is not an object the generator can write back.
void callback() {}

/// Providers with a wrong shape.
@Module(
  id: 'odd',
  providers: [
    Mode,
    Bind<void Function(), void Function()>(),
    Value(callback),
    Value(1, token: 'db'),
    Value(appConfig, token: null),
  ],
)
class OddProvidersModule {}
