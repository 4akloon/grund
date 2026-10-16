import 'package:code_builder/code_builder.dart';

import '../model/public_imports.dart';
import 'dart_string.dart';

/// Prefixes every import of the generated library: `grund` for the
/// core barrel, `i1`, `i2`, … for the others in order of first use;
/// `dart:core` stays unprefixed. Declarations of `package:grund/src/`
/// are imported from the barrel, and those of another package's `src/` from
/// the public library its [PublicImports] name.
///
/// `Allocator.simplePrefixing` names prefixes `_i1`, which the
/// `no_leading_underscores_for_library_prefixes` lint rejects.
final class ImportAllocator implements Allocator {
  /// The core barrel every generated library imports.
  static const grund = 'package:grund/grund.dart';

  /// Creates an allocator that imports from the libraries in [_public].
  ImportAllocator([this._public = PublicImports.none]);

  final PublicImports _public;
  final Map<String, String> _prefixes = {};

  @override
  String allocate(Reference reference) {
    final symbol = reference.symbol;
    if (symbol == null) {
      throw StateError(
        'A reference to library ${reference.url} has no symbol.',
      );
    }
    final url = switch (reference.url) {
      final String url when url.startsWith('package:grund/') => grund,
      final String url => _public.find(url, symbol) ?? url,
      null => null,
    };
    if (url == null || url == 'dart:core') return symbol;
    final prefix = _prefixes.putIfAbsent(
      url,
      () => url == grund ? 'grund' : 'i${_numbered + 1}',
    );
    return '$prefix.$symbol';
  }

  int get _numbered => _prefixes.keys.where((url) => url != grund).length;

  @override
  Iterable<Directive> get imports => [
    for (final MapEntry(key: url, value: prefix) in _prefixes.entries)
      Directive.import(DartString.escape(url), as: prefix),
  ];
}
