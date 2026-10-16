// Imports a module of another package straight from its `src/` file.
import 'package:grund/grund.dart' as grund;
import 'package:grund/annotations.dart';
// ignore: implementation_imports, the fixture is the case of a host that does it.
import 'package:other_pkg/src/other_module.dart';

/// Imports [OtherModule].
@Module(imports: [OtherModule()])
final class ViaSrcModule extends grund.Module {
  /// Creates the module.
  const ViaSrcModule();
}
