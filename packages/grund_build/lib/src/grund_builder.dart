import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:path/path.dart' as p;

import 'generated_outputs.dart';
import 'library_reach.dart';
import 'syntax_check.dart';

/// Writes the generated files of one library of `lib/`, as `grund_cli gen`
/// writes them: `X_module.g.dart` when `x.dart` declares `@Module`,
/// `X_api.g.dart` when it declares `@Api`.
///
/// One build step per input library. The step needs more than its input:
/// the module graph and dependency checks run over the modules the input
/// reaches. So it resolves the input and every library of the package that
/// the input reaches through imports and exports, collects and generates
/// them as one package (the CLI collects every library; the files of the
/// input do not depend on the unreached ones), and writes only the files of
/// the input. The step keeps no state, so its output depends on the sources
/// alone.
///
/// Problems are logged as errors, one per line, in the CLI's
/// `path:line:column: error: message [code]` form, but only those of the
/// input library and its part files: a problem in another library is
/// reported by the step of that library, so it is not reported once per
/// importer. A problem anywhere in the reached libraries, the input's own
/// or not, withholds the step's files; a step whose own library has no
/// problem then says which libraries do, so a missing file always has a
/// message.
final class GrundBuilder implements Builder {
  /// Creates the builder, generating with [generator].
  const GrundBuilder({this.generator = StandardGenerator.instance});

  /// The constructs that run.
  final GrundGenerator generator;

  /// Every Dart file may declare modules and APIs; an output that is not
  /// needed is not written, which build_runner accepts.
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': ['_module.g.dart', '_api.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (!await _isSource(buildStep, input)) return;
    final resolver = buildStep.resolver;
    final syntax = SyntaxCheck(input.package, resolver);
    final ownSyntax = await syntax.of(input);
    if (ownSyntax.isNotEmpty) return _fail(ownSyntax);
    final library = await resolver.libraryFor(input);
    final reached = LibraryReach.within(input.package, library);
    final broken = await _othersWithSyntaxProblems(syntax, reached, input);
    if (broken.isNotEmpty) return _withheld(input, broken);
    final result = generator.generate(
      generator.collector(input.package, '/${input.package}').collect(reached),
    );
    if (!result.isSuccess) return _failed(result, library, input);
    final unwritable = _unwritable(result.files, reached);
    if (unwritable.isNotEmpty) return _fail(unwritable);
    await _write(buildStep, result.files);
  }

  /// Reports a failed generation: the problems of the input's own library,
  /// or, when they are all elsewhere, which libraries have them.
  static void _failed(
    GenerationResult result,
    LibraryElement library,
    AssetId input,
  ) {
    final own = _ownDiagnostics(result, library, input.package);
    if (own.isNotEmpty) return _fail(own);
    _withheld(input, {
      for (final diagnostic in result.diagnostics) diagnostic.location.path,
    });
  }

  /// Fails the step that writes nothing for [input] because of problems in
  /// [paths] only, so a missing output never goes without a message even
  /// when the library with the problem is no input of this build.
  static void _withheld(AssetId input, Iterable<String> paths) {
    final sorted = paths.toSet().toList()..sort();
    final names = sorted.join(', ');
    final verb = sorted.length == 1 ? 'has' : 'have';
    log.severe('${input.path} was not generated: $names $verb problems');
  }

  /// The generated files that no reached library owns: a builder writes
  /// only `X_module.g.dart` and `X_api.g.dart`.
  static List<String> _unwritable(
    Map<String, String> files,
    List<LibraryElement> reached,
  ) {
    final owned = {
      for (final library in reached) ...[
        GeneratedNames.moduleLibraryPath(_pathOf(library)),
        ApiNames.partPath(_pathOf(library)),
      ],
    };
    return [
      for (final path in files.keys)
        if (!owned.contains(path))
          'grund_build cannot write $path: a construct generated it, and a '
              'build_runner builder writes only X_module.g.dart and '
              'X_api.g.dart next to a library. Generate this package with '
              'grund_cli gen.',
    ];
  }

  static String _pathOf(LibraryElement library) =>
      'lib/${library.uri.pathSegments.skip(1).join('/')}';

  /// Whether [input] is a library of `lib/` that is not itself generated.
  ///
  /// A part file is recognised by parsing it, not by asking the resolver,
  /// which throws for a part (or host) with syntax errors: the step of the
  /// host reports those, once.
  static Future<bool> _isSource(BuildStep step, AssetId input) async {
    if (!p.posix.isWithin('lib', input.path) || !input.path.endsWith('.dart')) {
      return false;
    }
    final content = await step.readAsString(input);
    if (GeneratedOutputs.hasGeneratedName(input.path) &&
        GeneratedOutputs.hasHeader(content)) {
      return false;
    }
    final unit = parseString(content: content, throwIfDiagnostics: false).unit;
    return !unit.directives.any((directive) => directive is PartOfDirective);
  }

  // Their errors are reported by their own steps; this step only refuses
  // to write while any source in its graph does not parse.
  static Future<Set<String>> _othersWithSyntaxProblems(
    SyntaxCheck syntax,
    List<LibraryElement> reached,
    AssetId input,
  ) async {
    final broken = <String>{};
    for (final library in reached) {
      final asset = AssetId.resolve(library.uri);
      if (asset == input || GeneratedOutputs.isOutput(library)) continue;
      if ((await syntax.of(asset)).isNotEmpty) broken.add(_pathOf(library));
    }
    return broken;
  }

  static List<Diagnostic> _ownDiagnostics(
    GenerationResult result,
    LibraryElement library,
    String package,
  ) {
    final own = {
      for (final fragment in library.fragments)
        p.posix.relative(fragment.source.fullName, from: '/$package'),
    };
    return [
      for (final diagnostic in result.diagnostics)
        if (own.contains(diagnostic.location.path)) diagnostic,
    ];
  }

  static Future<void> _write(BuildStep step, Map<String, String> files) async {
    final path = step.inputId.path;
    for (final name in [
      GeneratedNames.moduleLibraryPath(path),
      ApiNames.partPath(path),
    ]) {
      if (files[name] case final content?) {
        await step.writeAsString(AssetId(step.inputId.package, name), content);
      }
    }
  }

  static void _fail(Iterable<Object> problems) {
    for (final problem in problems) {
      log.severe('$problem');
    }
  }
}
