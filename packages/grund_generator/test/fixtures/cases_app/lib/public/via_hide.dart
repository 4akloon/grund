// Hides the module in the barrel import and imports its src file.
import 'package:grund/grund.dart' as grund;
import 'package:grund/annotations.dart';
// ignore: unused_import, the case is a hiding import that must stay unused.
import 'package:other_pkg/other_pkg.dart' hide OtherModule;
// ignore: implementation_imports, the fixture is the case of a host that does it.
import 'package:other_pkg/src/other_module.dart';

/// Imports OtherModule.
@Module(imports: [OtherModule()])
final class ViaHideModule extends grund.Module {
  /// Creates the module.
  const ViaHideModule();
}
