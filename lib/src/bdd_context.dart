import 'package:flutter/foundation.dart';

import 'bdd_base.dart' as bdd_framework show val, BddTableTerm;

// //////////////////////////////////////////////////////////////////////////////////////////////////

class BddContext {
  final BddTableValues example;

  final BddMultipleTableValues _table;

  BddTableRows table(String tableName) => BddTableRows(_table.row(tableName));

  BddContext(this.example, this._table);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BddContext &&
          runtimeType == other.runtimeType &&
          example == other.example &&
          _table == other._table;

  @override
  int get hashCode => example.hashCode ^ _table.hashCode;
}

// //////////////////////////////////////////////////////////////////////////////////////////////////

class BddTableRows {
  final List<BddTableValues> _values;

  BddTableRows(this._values);

  /// Example:
  /// ctx.table('notifications').row(0).val('read') as bool;
  BddTableValues row(int index) {
    if (index < 0 || index >= _values.length)
      throw AssertionError("You can't get table row($index), since range is 0..${_values.length}.");
    else
      return _values[index];
  }

  /// Return the first row it finds with the given name/value pair. Example:
  /// ctx.table('notifications').rowWhere(name: 'property', value: 'lastPrice').val('market') as Money;
  /// If no name/value pair is found, an error is thrown.
  BddTableValues rowWhere({required String name, required Object? value}) {
    return _values.firstWhere(
      (BddTableValues btv) => btv.val(name) == value,
      orElse: () {
        throw AssertionError('There is no table with name:"$name" and value: "$name".');
      },
    );
  }

  /// Example:
  /// ctx.table('notifications').rows;
  List<BddTableValues> get rows => _values.toList();

  @override
  String toString() => 'BddTableRows{$_values}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BddTableRows) &&
          (runtimeType == other.runtimeType) &&
          listEquals(_values, other._values);

  @override
  int get hashCode => _values.hashCode;
}

// //////////////////////////////////////////////////////////////////////////////////////////////////

class BddMultipleTableValues {
  final Map<String, List<BddTableValues>> _tables;

  BddMultipleTableValues(this._tables);

  factory BddMultipleTableValues.from(List<bdd_framework.BddTableTerm> tableTerms) {
    Map<String, List<BddTableValues>> _tables = {};
    for (bdd_framework.BddTableTerm _table in tableTerms) {
      List<BddTableValues> tableValues = _table.rows.map((r) => BddTableValues.from(r.values)).toList();

      _tables[_table.tableName] = tableValues;
    }
    return BddMultipleTableValues(_tables);
  }

  List<BddTableValues> row(String tableName) {
    var table = _tables[tableName];
    if (table == null) throw AssertionError('There is no table named "$tableName".');
    return table;
  }

  @override
  String toString() => _tables.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BddMultipleTableValues) &&
          (runtimeType == other.runtimeType) &&
          mapEquals(_tables, other._tables);

  @override
  int get hashCode => _tables.hashCode;
}

// //////////////////////////////////////////////////////////////////////////////////////////////////

/// The example values are encapsulated as a [BddTableValues] object to be used by the code runs.
/// In other words, the test code may read the example values from this.
class BddTableValues {
  final Map<String, Object?> _map;

  BddTableValues(this._map);

  factory BddTableValues.from(Iterable<bdd_framework.val>? exampleRow) {
    Map<String, Object?> _map = {};
    exampleRow ??= {};
    for (bdd_framework.val _val in exampleRow) {
      _map[_val.name] = _val.value;
    }
    return BddTableValues(_map);
  }

  dynamic val(String header) => _map[header];

  @override
  String toString() => _map.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BddTableValues) &&
          (runtimeType == other.runtimeType) &&
          mapEquals(_map, other._map);

  @override
  int get hashCode => _map.hashCode;
}

// //////////////////////////////////////////////////////////////////////////////////////////////////
