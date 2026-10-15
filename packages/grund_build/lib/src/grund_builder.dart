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
/// or not, fails the step as far as writing goes: nothing is written then.
final class GrundBuilder implements Builder {
  /// Creates the builder, generating with [generator].
  const GrundBuilder({this.generator = defaultGenerator});

  /// The constructs the builder runs unless it is given others: modules
  /// with their bindings, and `@Api` classes with their routes; the set
  /// `grund_cli` runs.
  static const defaultGenerator = GrundGenerator([
    ModuleConstruct(),
    ApiConstruct(),
  ]);

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
    if (await _othersHaveSyntaxProblems(syntax, reached, input)) return;
    final result = generator.generate(
      generator.collector(input.package, '/${input.package}').collect(reached),
    );
    if (!result.isSuccess) {
      return _fail(_ownDiagnostics(result, library, input.package));
    }
    await _write(buildStep, result.files);
  }

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
  static Future<bool> _othersHaveSyntaxProblems(
    SyntaxCheck syntax,
    List<LibraryElement> reached,
    AssetId input,
  ) async {
    for (final library in reached) {
      final asset = AssetId.resolve(library.uri);
      if (asset == input || GeneratedOutputs.isOutput(library)) continue;
      if ((await syntax.of(asset)).isNotEmpty) return true;
    }
    return false;
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
