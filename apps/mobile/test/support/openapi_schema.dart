/// Validates a JSON body against a schema in the generated API contract,
/// `packages/api-client/openapi.json` — the file the backend's own
/// `make client-check` keeps in step with FastAPI.
///
/// Covers what the farm DTOs use: `$ref`, `anyOf`, `type`, `enum`, `format`
/// (`uuid`, `date`, `date-time`), string length and `pattern`, number bounds,
/// `required` and `additionalProperties: false`. Anything it does not
/// understand is reported as an error rather than passed, so a contract that
/// outgrows it fails loudly.
library;

import 'dart:convert';
import 'dart:io';

class OpenApi {
  OpenApi._(this._schemas);

  /// The contract, read from the monorepo. Tests run from `apps/mobile`.
  static final OpenApi contract = OpenApi._(
    ((jsonDecode(
              File('../../packages/api-client/openapi.json').readAsStringSync(),
            ) as Map<String, dynamic>)['components']
            as Map<String, dynamic>)['schemas']
        as Map<String, dynamic>,
  );

  final Map<String, dynamic> _schemas;

  bool has(String name) => _schemas.containsKey(name);

  /// Every way [value] breaks schema [name]; empty when it conforms.
  List<String> errors(String name, Object? value) {
    final out = <String>[];
    _check({r'$ref': '#/components/schemas/$name'}, value, name, out);
    return out;
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );
  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static const _known = {
    r'$ref',
    'anyOf',
    'type',
    'enum',
    'format',
    'maxLength',
    'minLength',
    'pattern',
    'minimum',
    'maximum',
    'exclusiveMinimum',
    'properties',
    'required',
    'additionalProperties',
    'items',
    'title',
    'default',
    'description',
    'examples',
  };

  void _check(
    Map<String, dynamic> schema,
    Object? value,
    String at,
    List<String> out,
  ) {
    for (final key in schema.keys) {
      if (!_known.contains(key)) out.add('$at: unsupported keyword $key');
    }
    final ref = schema[r'$ref'];
    if (ref is String) {
      final name = ref.split('/').last;
      final target = _schemas[name];
      if (target == null) {
        out.add('$at: unknown schema $name');
        return;
      }
      _check(target as Map<String, dynamic>, value, at, out);
      return;
    }
    final anyOf = schema['anyOf'];
    if (anyOf is List) {
      final branches = [
        for (final branch in anyOf)
          () {
            final errors = <String>[];
            _check(branch as Map<String, dynamic>, value, at, errors);
            return errors;
          }(),
      ];
      if (branches.every((b) => b.isNotEmpty)) {
        out.add('$at: matches no anyOf branch (${branches.first.first})');
      }
      return;
    }
    final type = schema['type'];
    switch (type) {
      case 'null':
        if (value != null) out.add('$at: expected null');
        return;
      case 'string':
        if (value is! String) {
          out.add('$at: expected string, got $value');
          return;
        }
        _string(schema, value, at, out);
      case 'integer':
        if (value is! int) {
          out.add('$at: expected integer, got $value');
          return;
        }
        _number(schema, value, at, out);
      case 'number':
        if (value is! num) {
          out.add('$at: expected number, got $value');
          return;
        }
        _number(schema, value, at, out);
      case 'boolean':
        if (value is! bool) out.add('$at: expected boolean, got $value');
      case 'array':
        if (value is! List) {
          out.add('$at: expected array');
          return;
        }
        final items = schema['items'];
        if (items is Map<String, dynamic>) {
          for (var i = 0; i < value.length; i++) {
            _check(items, value[i], '$at[$i]', out);
          }
        }
      case 'object':
        if (value is! Map) {
          out.add('$at: expected object, got $value');
          return;
        }
        _object(schema, value.cast<String, Object?>(), at, out);
      case null:
        break;
      default:
        out.add('$at: unsupported type $type');
    }
    final allowed = schema['enum'];
    if (allowed is List && !allowed.contains(value)) {
      out.add('$at: $value not in $allowed');
    }
  }

  void _string(
    Map<String, dynamic> schema,
    String value,
    String at,
    List<String> out,
  ) {
    final max = schema['maxLength'], min = schema['minLength'];
    if (max is int && value.length > max) out.add('$at: longer than $max');
    if (min is int && value.length < min) out.add('$at: shorter than $min');
    final pattern = schema['pattern'];
    // Python's `re.search` semantics: the pattern may match anywhere.
    if (pattern is String && !RegExp(pattern).hasMatch(value)) {
      out.add('$at: does not match $pattern');
    }
    switch (schema['format']) {
      case 'uuid':
        if (!_uuid.hasMatch(value)) out.add('$at: not a uuid');
      case 'date':
        if (!_date.hasMatch(value) || DateTime.tryParse(value) == null) {
          out.add('$at: not a date');
        }
      case 'date-time':
        if (DateTime.tryParse(value) == null || !value.contains('T')) {
          out.add('$at: not a date-time');
        }
      case null:
        break;
      case final other:
        out.add('$at: unsupported format $other');
    }
  }

  void _number(
    Map<String, dynamic> schema,
    num value,
    String at,
    List<String> out,
  ) {
    final min = schema['minimum'], max = schema['maximum'];
    final above = schema['exclusiveMinimum'];
    if (min is num && value < min) out.add('$at: below $min');
    if (max is num && value > max) out.add('$at: above $max');
    if (above is num && value <= above) out.add('$at: not above $above');
  }

  void _object(
    Map<String, dynamic> schema,
    Map<String, Object?> value,
    String at,
    List<String> out,
  ) {
    final properties =
        (schema['properties'] as Map<String, dynamic>?) ?? const {};
    for (final name in (schema['required'] as List?) ?? const []) {
      if (!value.containsKey(name)) out.add('$at: missing $name');
    }
    for (final entry in value.entries) {
      final property = properties[entry.key];
      if (property == null) {
        if (schema['additionalProperties'] == false) {
          out.add('$at: unexpected field ${entry.key}');
        }
        continue;
      }
      _check(
        property as Map<String, dynamic>,
        entry.value,
        '$at.${entry.key}',
        out,
      );
    }
  }
}
