// A module providing classes whose constructors fail the checks.
import 'package:grund/grund.dart' hide Controller, Module;
import 'package:grund_annotations/grund_annotations.dart';

import '../modules/basic.dart';
import 'constructors.dart';

final class _Port {}

const _port = Token<_Port>('port');

/// Injects a token of a private type.
@Injectable()
final class PrivateToken {
  /// Creates it.
  PrivateToken(@Inject(_port) this.port);

  /// The port.
  final Object port;
}

/// Provides every class of `constructors.dart` worth checking.
@Module(
  providers: [
    Plain,
    Shape,
    Optional,
    BadTokens,
    PrivateToken,
    Fine,
    SystemClock,
  ],
)
class ProvidersModule {}
