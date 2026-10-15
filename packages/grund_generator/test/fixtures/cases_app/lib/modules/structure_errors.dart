// Module graphs Application.create would reject.
import 'package:grund_annotations/grund_annotations.dart';

import 'basic.dart';

final class _Secret {
  const _Secret();
}

/// Shares its id with [SecondModule].
@Module(id: 'shared')
class FirstModule {}

/// Shares its id with [FirstModule].
@Module(id: 'shared')
class SecondModule {}

/// Imports [PongModule], which imports it back.
@Module(imports: [PongModule])
class PingModule {}

/// Imports [PingModule].
@Module(imports: [PingModule])
class PongModule {}

/// Declares a provider twice, exports what it does not have, and provides
/// a value generated code cannot write.
@Module(
  providers: [SystemClock, SystemClock, Value(_Secret())],
  exports: [Repo, SecondModule],
)
class SloppyModule {}
