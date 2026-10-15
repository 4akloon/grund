/// The type of a path, query, header or cookie parameter, which decides the
/// reader of `Params` that fills it.
enum ValueKind {
  /// `String`: `string`.
  string('string'),

  /// `int`: `integer`.
  integer('integer'),

  /// `double`: `decimal`.
  decimal('decimal'),

  /// `bool`: `boolean`.
  boolean('boolean'),

  /// `DateTime`: `dateTime`.
  dateTime('dateTime'),

  /// `Uri`: `uri`.
  uri('uri'),

  /// An enum: `enumOf`.
  enumeration('enumOf'),

  /// `List<String>` (repeated parameters): `all`.
  stringList('all'),

  /// Any other type: the parameter cannot come from a request part.
  unsupported('');

  const ValueKind(this.reader);

  /// The `Params` method that reads the value; the nullable variant adds
  /// `OrNull`.
  final String reader;
}
