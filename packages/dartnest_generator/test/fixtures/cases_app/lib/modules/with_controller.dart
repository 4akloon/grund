// A module that lists a controller of this package.
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// A controller.
@Controller('/ping')
class PingController {}

/// Serves it.
@Module(controllers: [PingController])
class PingModule {}
