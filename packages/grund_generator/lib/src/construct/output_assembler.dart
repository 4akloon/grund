import 'dart:collection';

import 'package:path/path.dart' as p;

import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../emit/library_writer.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import '../model/public_imports.dart';
import 'file_unit.dart';
import 'generated_unit.dart';
import 'library_unit.dart';
import 'part_unit.dart';

/// Joins the units of all constructs into files: the units of one path
/// into one library, one part file or one plain file.
///
/// A path no unit targets is not written: a package without modules has
/// no files.
final class OutputAssembler {
  /// Creates the assembler for [package].
  const OutputAssembler(this.package);

  /// The package being generated.
  final PackageModel package;

  /// The files of [units] by path, and the diagnostics of declarations
  /// that share a name within one file or whose library and part would
  /// share one path (no file is written for such a path).
  ///
  /// Throws [StateError] when other units of different kinds (or parts of
  /// different hosts) share a path, or a unit is of a kind this generator
  /// does not write: constructs that disagree are a programming error.
  ({Map<String, String> files, List<Diagnostic> problems}) assemble(
    List<GeneratedUnit> units,
  ) {
    final byPath = SplayTreeMap<String, List<GeneratedUnit>>();
    for (final unit in units) {
      byPath.putIfAbsent(unit.path, () => []).add(unit);
    }
    final targets = byPath.keys.toSet();
    final files = <String, String>{};
    final problems = <Diagnostic>[];
    for (final MapEntry(key: path, value: group) in byPath.entries) {
      final conflicts = _conflictingKinds(path, group);
      problems
        ..addAll(conflicts)
        ..addAll(_duplicateNames(group));
      if (conflicts.isEmpty) files[path] = _write(path, group, targets);
    }
    return (files: files, problems: problems..sort());
  }

  String _write(String path, List<GeneratedUnit> group, Set<String> targets) {
    if (group.every((unit) => unit is LibraryUnit)) {
      return LibraryWriter.write(
        packageName: package.packageName,
        languageVersion: package.languageVersion,
        declarations: [for (final unit in group) (unit as LibraryUnit).spec],
        publicImports: _publicImports(path),
      );
    }
    final parts = group.whereType<PartUnit>().toList();
    final hosts = {for (final part in parts) part.hostPath};
    if (parts.length == group.length && hosts.length == 1) {
      _requireHost(path, hosts.single, targets);
      return LibraryWriter.writePart(
        partOf: p.posix.relative(hosts.single, from: p.posix.dirname(path)),
        languageVersion: package.languageVersion,
        declarations: [for (final part in parts) part.spec],
      );
    }
    if (group case [FileUnit(:final content)]) return content;
    throw StateError(
      'The generated units for $path cannot form one file: '
      '${group.map((unit) => unit.runtimeType).join(', ')}.',
    );
  }

  // The library at [path] is the output of one source library.
  PublicImports _publicImports(String path) {
    for (final MapEntry(key: source, value: imports)
        in package.publicImports.entries) {
      if (GeneratedNames.outputPath(source) == path) return imports;
    }
    return PublicImports.none;
  }

  // A part of nothing, or of itself, is a construct bug, like the other
  // path disagreements.
  void _requireHost(String path, String host, Set<String> targets) {
    if (host != path &&
        (targets.contains(host) || package.libraryPaths.contains(host))) {
      return;
    }
    throw StateError(
      'The part $path belongs to $host, which is neither a source library '
      'of the package nor another generated file.',
    );
  }

  // A library and a part cannot both be the file at one path: with the
  // fixed output names, that is two kinds of declaration in one source
  // library, which the user resolves by splitting it.
  static List<Diagnostic> _conflictingKinds(
    String path,
    List<GeneratedUnit> group,
  ) {
    final library = group.whereType<LibraryUnit>().firstOrNull;
    final part = group.whereType<PartUnit>().firstOrNull;
    if (library == null || part == null) return const [];
    return [
      for (final (here, other) in [
        (library.origin, part.origin),
        (part.origin, library.origin),
      ])
        Diagnostic(
          DiagnosticCode.conflictingOutputs,
          here,
          'This declaration and the one at $other would be generated into '
          '$path as a library and as a part of a library. Declare them in '
          'separate libraries.',
        ),
    ];
  }

  static List<Diagnostic> _duplicateNames(List<GeneratedUnit> group) {
    final first = <String, GeneratedUnit>{};
    return [
      for (final unit in group)
        if (_declaration(unit) case (final name, final origin))
          if (first.putIfAbsent(name, () => unit) case final other
              when other != unit)
            Diagnostic(
              DiagnosticCode.duplicateGeneratedName,
              origin,
              'Generated name $name is used twice: for the declaration at '
              '${_declaration(other)?.$2} and for this one. Rename one of '
              'them.',
            ),
    ];
  }

  static (String, SourceLocation)? _declaration(GeneratedUnit unit) =>
      switch (unit) {
        LibraryUnit(:final name, :final origin) => (name, origin),
        PartUnit(:final name, :final origin) => (name, origin),
        _ => null,
      };
}
