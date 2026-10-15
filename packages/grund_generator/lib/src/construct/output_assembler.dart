import 'dart:collection';

import 'package:path/path.dart' as p;

import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../diagnostic/source_location.dart';
import '../emit/library_writer.dart';
import '../model/generated_names.dart';
import '../model/package_model.dart';
import 'file_unit.dart';
import 'generated_unit.dart';
import 'library_unit.dart';
import 'part_unit.dart';

/// Joins the units of all constructs into files: the units of one path
/// into one library, one part file or one plain file.
///
/// The package library `lib/<package>.grund.dart` is always written, even
/// without units, so a driver can replace the one it generated before.
final class OutputAssembler {
  /// Creates the assembler for [package].
  const OutputAssembler(this.package);

  /// The package being generated.
  final PackageModel package;

  /// The files of [units] by path, or the diagnostics of declarations
  /// that share a name within one file.
  ///
  /// Throws [StateError] when units of different kinds (or parts of
  /// different hosts) share a path, or a unit is of a kind this generator
  /// does not write: constructs that disagree are a programming error.
  ({Map<String, String> files, List<Diagnostic> duplicates}) assemble(
    List<GeneratedUnit> units,
  ) {
    final byPath = SplayTreeMap<String, List<GeneratedUnit>>()
      ..[GeneratedNames.libraryPath(package.packageName)] = [];
    for (final unit in units) {
      byPath.putIfAbsent(unit.path, () => []).add(unit);
    }
    final files = <String, String>{};
    final duplicates = <Diagnostic>[];
    for (final MapEntry(key: path, value: group) in byPath.entries) {
      duplicates.addAll(_duplicateNames(group));
      files[path] = _write(path, group);
    }
    return (files: files, duplicates: duplicates..sort());
  }

  String _write(String path, List<GeneratedUnit> group) {
    if (group.every((unit) => unit is LibraryUnit)) {
      return LibraryWriter.write(
        packageName: package.packageName,
        languageVersion: package.languageVersion,
        declarations: [for (final unit in group) (unit as LibraryUnit).spec],
      );
    }
    final parts = group.whereType<PartUnit>().toList();
    final hosts = {for (final part in parts) part.hostPath};
    if (parts.length == group.length && hosts.length == 1) {
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
