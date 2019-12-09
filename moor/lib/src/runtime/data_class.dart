import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:moor/moor.dart';

/// Common interface for objects which can be inserted or updated into a
/// database.
@optionalTypeArgs
abstract class Insertable<D extends DataClass> {
  /// Converts this object into a companion that can be used for inserts. On
  /// data classes, [nullToAbsent] will map `null` fields to [Value.absent()].
  /// Otherwise, null fields will be mapped to `Value(null)`.
  ///
  /// Mainly used internally by moor.
  UpdateCompanion<D> createCompanion(bool nullToAbsent);
}

/// A common supertype for all data classes generated by moor. Data classes are
/// immutable structures that represent a single row in a database table.
abstract class DataClass {
  /// Constant constructor so that generated data classes can be constant.
  const DataClass();

  /// Converts this object into a representation that can be encoded with
  /// [json]. The [serializer] can be used to configure how individual values
  /// will be encoded.
  Map<String, dynamic> toJson();

  /// Converts this object into a json representation. The [serializer] can be
  /// used to configure how individual values will be encoded.
  String toJsonString() {
    return json.encode(toJson());
  }

  /// Used internally be generated code
  @protected
  static dynamic parseJson(String jsonString) {
    return json.decode(jsonString);
  }
}

/// An update companion for a [DataClass] which is used to write data into a
/// database using [InsertStatement.insert] or [UpdateStatement.write].
///
/// See also:
/// - the explanation in the changelog for 1.5
/// - https://github.com/simolus3/moor/issues/25
abstract class UpdateCompanion<D extends DataClass> implements Insertable<D> {
  /// Constant constructor so that generated companion classes can be constant.
  const UpdateCompanion();

  @override
  UpdateCompanion<D> createCompanion(bool nullToAbsent) {
    return this;
  }
}

/// A wrapper around arbitrary data [T] to indicate presence or absence
/// explicitly. We can use [Value]s in companions to distinguish between null
/// and absent values.
class Value<T> {
  /// Whether this [Value] wrapper contains a present [value] that should be
  /// inserted or updated.
  final bool present;

  /// If this value is [present], contains the value to update or insert.
  final T value;

  /// Create a (present) value by wrapping the [value] provided.
  const Value(this.value) : present = true;

  /// Create an absent value that will not be written into the database, the
  /// default value or null will be used instead.
  const Value.absent()
      : value = null,
        present = false;
}

/// Serializer responsible for mapping atomic types from and to json.
abstract class ValueSerializer {
  /// Constant super-constructor to allow constant child classes.
  const ValueSerializer();

  /// The default serializer encodes date times as a unix-timestamp in
  /// milliseconds.
  const factory ValueSerializer.defaults() = _DefaultValueSerializer;

  /// Converts the [value] to something that can be passed to
  /// [JsonCodec.encode].
  dynamic toJson<T>(T value);

  /// Inverse of [toJson]: Converts a value obtained from [JsonCodec.decode]
  /// into a value that can be hold by data classes.
  T fromJson<T>(dynamic json);
}

class _DefaultValueSerializer extends ValueSerializer {
  const _DefaultValueSerializer();

  @override
  T fromJson<T>(json) {
    if (T == DateTime) {
      if (json == null) {
        return null;
      } else {
        return DateTime.fromMillisecondsSinceEpoch(json as int) as T;
      }
    }

    return json as T;
  }

  @override
  dynamic toJson<T>(T value) {
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }

    return value;
  }
}
