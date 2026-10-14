/// A generated annotated package of `4 * features + 1` libraries: per
/// feature a repository, a service, a controller and a module, plus the
/// root module that imports every feature.
abstract final class BenchmarkSources {
  /// The files of the package (relative path → content).
  static Map<String, String> files(int features) => {
    for (var i = 0; i < features; i++) ..._feature(i),
    'lib/app.dart': _root(features),
  };

  /// The controller of feature [i] with one more route.
  static String changedController(int i) =>
      _controller(i).replaceFirst('@Get()', "@Get('/v2')");

  /// The path of feature [i]'s controller.
  static String controllerPath(int i) => 'lib/src/f$i/controller.dart';

  static Map<String, String> _feature(int i) => {
    'lib/src/f$i/repository.dart':
        '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

@Injectable()
final class Repository$i {
  List<String> all() => ['item $i'];
}
''',
    'lib/src/f$i/service.dart':
        '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'repository.dart';

@Injectable()
final class Service$i {
  Service$i(this.repository);

  final Repository$i repository;

  List<String> list() => repository.all();
}
''',
    controllerPath(i): _controller(i),
    'lib/src/f$i/module.dart':
        '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'controller.dart';
import 'repository.dart';
import 'service.dart';

@Module(
  id: 'f$i',
  providers: [Repository$i, Service$i],
  controllers: [Feature${i}Controller],
)
final class Feature${i}Module {}
''',
  };

  static String _controller(int i) =>
      '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'service.dart';

@Controller('/f$i')
final class Feature${i}Controller {
  Feature${i}Controller(this.service);

  final Service$i service;

  @Get()
  List<String> list() => service.list();

  @Get('/:id')
  Map<String, Object?> one(@Param('id') int id) => {'id': id};
}
''';

  static String _root(int features) {
    final imports = [
      for (var i = 0; i < features; i++) "import 'src/f$i/module.dart';",
    ];
    final modules = [for (var i = 0; i < features; i++) 'Feature${i}Module'];
    return '''
import 'package:dartnest_annotations/dartnest_annotations.dart';

${imports.join('\n')}

@Module(id: 'app', imports: [${modules.join(', ')}])
final class AppModule {}
''';
  }
}
