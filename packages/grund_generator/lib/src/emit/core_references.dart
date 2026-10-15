import 'package:code_builder/code_builder.dart';

import 'dart_string.dart';
import 'import_allocator.dart';

/// References to the declarations of the core barrel that generated code
/// uses.
abstract final class CoreReferences {
  /// [symbol] of `package:grund/grund.dart`.
  static Reference grund(String symbol) => refer(symbol, ImportAllocator.grund);

  /// `Key<T>` with type argument [type] and an optional [name].
  static Expression key(Reference type, [String? name]) =>
      grund('Key').newInstance(
        [if (name != null) DartString.expression(name)],
        const {},
        [type],
      );
}
