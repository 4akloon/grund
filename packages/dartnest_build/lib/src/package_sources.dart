import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';

/// The Dart sources of a package's `lib/` as one build step sees them:
/// every `*.dart` asset except generated `*.dartnest.dart` files, sorted by
/// path, the files `dartnest_cli gen` reads.
final class PackageSources {
  PackageSources._(this._step, this.assets);

  /// Finds the sources of the package [step] builds.
  static Future<PackageSources> find(BuildStep step) async {
    final assets = await step
        .findAssets(_dartFiles)
        .where((asset) => !asset.path.endsWith('.dartnest.dart'))
        .toList();
    return PackageSources._(step, assets..sort());
  }

  static final _dartFiles = Glob('lib/**.dart');

  final BuildStep _step;

  /// The sources, sorted by path.
  final List<AssetId> assets;

  /// The resolved libraries among [assets]; part files are skipped.
  Future<List<LibraryElement>> libraries() async {
    final resolver = _step.resolver;
    return [
      for (final asset in assets)
        if (await resolver.isLibrary(asset)) await resolver.libraryFor(asset),
    ];
  }
}
