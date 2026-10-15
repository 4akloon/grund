/// A generated annotated package of `4 * features + 1` libraries: per
/// feature a repository, a service, an API and a module, plus the
/// root module that imports every feature.
abstract final class BenchmarkSources {
  /// The files of the package (relative path → content).
  static Map<String, String> files(int features) => {
    for (var i = 0; i < features; i++) ..._feature(i),
    'lib/app.dart': _root(features),
  };

  /// The API of feature [i] with one more route, `/v<revision>`.
  static String changedApi(int i, {int revision = 2}) =>
      _api(i).replaceFirst("@Get('/')", "@Get('/v$revision')");

  /// The path of feature [i]'s API.
  static String apiPath(int i) => 'lib/src/f$i/api.dart';

  static Map<String, String> _feature(int i) => {
    'lib/src/f$i/repository.dart':
        '''
import 'package:grund/annotations.dart';

@Injectable()
final class Repository$i {
  List<String> all() => ['item $i'];
}
''',
    'lib/src/f$i/service.dart':
        '''
import 'package:grund/annotations.dart';

import 'repository.dart';

@Injectable()
final class Service$i {
  Service$i(this.repository);

  final Repository$i repository;

  List<String> list() => repository.all();
}
''',
    apiPath(i): _api(i),
    'lib/src/f$i/module.dart':
        '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'api.dart';
import 'module.g.dart';
import 'repository.dart';
import 'service.dart';

@Module(providers: [Repository$i, Service$i, Feature${i}Api])
final class Feature${i}Module extends grund.Module with \$Feature${i}Module {
  const Feature${i}Module();
}
''',
  };

  static String _api(int i) =>
      '''
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'service.dart';

part 'api.g.dart';

@Api('/f$i')
final class Feature${i}Api {
  Feature${i}Api(this.service);

  final Service$i service;

  @Get('/')
  List<String> list() => service.list();

  @Get('/:id')
  Map<String, Object?> one(@Path() int id) => {'id': id};
}
''';

  static String _root(int features) {
    final imports = [
      for (var i = 0; i < features; i++) "import 'src/f$i/module.dart';",
    ];
    final modules = [for (var i = 0; i < features; i++) 'Feature${i}Module()'];
    return '''
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'app_module.g.dart';
${imports.join('\n')}

@Module(imports: [${modules.join(', ')}])
final class AppModule extends grund.Module with \$AppModule {
  const AppModule();
}
''';
  }
}
