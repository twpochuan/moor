part of '../query_builder.dart';

/// Any sql expression that evaluates to some generic value. This does not
/// include queries (which might evaluate to multiple values) but individual
/// columns, functions and operators.
abstract class Expression<D, T extends SqlType<D>> implements Component {
  /// Constant constructor so that subclasses can be constant.
  const Expression();

  /// The precedence of this expression. This can be used to automatically put
  /// parentheses around expressions as needed.
  Precedence get precedence => Precedence.unknown;

  /// Whether this expression is a literal. Some use-sites need to put
  /// parentheses around non-literals.
  bool get isLiteral => false;

  /// Whether this expression is equal to the given expression.
  Expression<bool, BoolType> equalsExp(Expression<D, T> compare) =>
      _Comparison.equal(this, compare);

  /// Whether this column is equal to the given value, which must have a fitting
  /// type. The [compare] value will be written
  /// as a variable using prepared statements, so there is no risk of
  /// an SQL-injection.
  Expression<bool, BoolType> equals(D compare) =>
      _Comparison.equal(this, Variable<D, T>(compare));

  /// Casts this expression to an expression with [D] and [T] parameter without
  /// changing what's written with [writeInto]. In particular, using [dartCast]
  /// will __NOT__ generate a `CAST` expression in sql.
  ///
  /// This method is used internally by moor.
  Expression<D2, T2> dartCast<D2, T2 extends SqlType<D2>>() {
    return _CastExpression<D, D2, T, T2>(this);
  }

  /// An expression that is true if `this` resolves to any of the values in
  /// [values].
  Expression<bool, BoolType> isIn(Iterable<D> values) {
    return _InExpression(this, values, false);
  }

  /// An expression that is true if `this` does not resolve to any of the values
  /// in [values].
  Expression<bool, BoolType> isNotIn(Iterable<D> values) {
    return _InExpression(this, values, true);
  }

  /// Writes this expression into the [GenerationContext], assuming that there's
  /// an outer expression with [precedence]. If the [Expression.precedence] of
  /// `this` expression is lower, it will be wrapped in
  ///
  /// See also:
  ///  - [Component.writeInto], which doesn't take any precedence relation into
  ///  account.
  void writeAroundPrecedence(GenerationContext context, Precedence precedence) {
    if (this.precedence < precedence) {
      context.buffer.write('(');
      writeInto(context);
      context.buffer.write(')');
    } else {
      writeInto(context);
    }
  }

  /// If this [Expression] wraps an [inner] expression, this utility method can
  /// be used inside [writeInto] to write that inner expression while wrapping
  /// it in parentheses if necessary.
  @protected
  void writeInner(GenerationContext ctx, Expression inner) {
    assert(precedence != Precedence.unknown,
        "Expressions with unknown precedence shouldn't have inner expressions");
    inner.writeAroundPrecedence(ctx, precedence);
  }
}

/// Used to order the precedence of sql expressions so that we can avoid
/// unnecessary parens when generating sql statements.
class Precedence implements Comparable<Precedence> {
  /// Higher means higher precedence.
  final int _value;

  const Precedence._(this._value);

  @override
  int compareTo(Precedence other) {
    return _value.compareTo(other._value);
  }

  @override
  int get hashCode => _value;

  @override
  bool operator ==(other) {
    // runtimeType comparison isn't necessary, the private constructor prevents
    // subclasses
    return other is Precedence && other._value == _value;
  }

  /// Returns true if this [Precedence] is lower than [other].
  bool operator <(Precedence other) => compareTo(other) < 0;

  /// Returns true if this [Precedence] is lower or equal to [other].
  bool operator <=(Precedence other) => compareTo(other) <= 0;

  /// Returns true if this [Precedence] is higher than [other].
  bool operator >(Precedence other) => compareTo(other) > 0;

  /// Returns true if this [Precedence] is higher or equal to [other].
  bool operator >=(Precedence other) => compareTo(other) >= 0;

  /// Precedence is unknown, assume lowest. This can be used for a
  /// [CustomExpression] to always put parens around it.
  static const Precedence unknown = Precedence._(-1);

  /// Precedence for the `OR` operator in sql
  static const Precedence or = Precedence._(10);

  /// Precedence for the `AND` operator in sql
  static const Precedence and = Precedence._(11);

  /// Precedence for most of the comparisons operators in sql, including
  /// equality, is (not) checks, in, like, glob, match, regexp.
  static const Precedence comparisonEq = Precedence._(12);

  /// Precedence for the <, <=, >, >= operators in sql
  static const Precedence comparison = Precedence._(13);

  /// Precedence for bitwise operators in sql
  static const Precedence bitwise = Precedence._(14);

  /// Precedence for the (binary) plus and minus operators in sql
  static const Precedence plusMinus = Precedence._(15);

  /// Precedence for the *, / and % operators in sql
  static const Precedence mulDivide = Precedence._(16);

  /// Precedence for the || operator in sql
  static const Precedence stringConcatenation = Precedence._(17);

  /// Precedence for unary operators in sql
  static const Precedence unary = Precedence._(20);

  /// Precedence for postfix operators (like collate) in sql
  static const Precedence postfix = Precedence._(21);

  /// Highest precedence in sql, used for variables and literals.
  static const Precedence primary = Precedence._(100);
}

/// An expression that looks like "$a operator $b", where $a and $b itself
/// are expressions and the operator is any string.
abstract class _InfixOperator<D, T extends SqlType<D>>
    extends Expression<D, T> {
  /// The left-hand side of this expression
  Expression get left;

  /// The right-hand side of this expresion
  Expression get right;

  /// The sql operator to write
  String get operator;

  @override
  void writeInto(GenerationContext context) {
    writeInner(context, left);
    context.writeWhitespace();
    context.buffer.write(operator);
    context.writeWhitespace();
    writeInner(context, right);
  }
}

class _BaseInfixOperator<D, T extends SqlType<D>> extends _InfixOperator<D, T> {
  @override
  final Expression<D, T> left;

  @override
  final String operator;

  @override
  final Expression<D, T> right;

  @override
  final Precedence precedence;

  _BaseInfixOperator(this.left, this.operator, this.right,
      {this.precedence = Precedence.unknown});
}

/// Defines the possible comparison operators that can appear in a [_Comparison].
enum _ComparisonOperator {
  /// '<' in sql
  less,

  /// '<=' in sql
  lessOrEqual,

  /// '=' in sql
  equal,

  /// '>=' in sql
  moreOrEqual,

  /// '>' in sql
  more
}

/// An expression that compares two child expressions.
class _Comparison extends _InfixOperator<bool, BoolType> {
  static const Map<_ComparisonOperator, String> _operatorNames = {
    _ComparisonOperator.less: '<',
    _ComparisonOperator.lessOrEqual: '<=',
    _ComparisonOperator.equal: '=',
    _ComparisonOperator.moreOrEqual: '>=',
    _ComparisonOperator.more: '>'
  };

  @override
  final Expression left;
  @override
  final Expression right;

  /// The operator to use for this comparison
  final _ComparisonOperator op;

  @override
  String get operator => _operatorNames[op];

  @override
  Precedence get precedence {
    if (op == _ComparisonOperator.equal) {
      return Precedence.comparisonEq;
    } else {
      return Precedence.comparison;
    }
  }

  /// Constructs a comparison from the [left] and [right] expressions to compare
  /// and the [ComparisonOperator] [op].
  _Comparison(this.left, this.op, this.right);

  /// Like [Comparison(left, op, right)], but uses [_ComparisonOperator.equal].
  _Comparison.equal(this.left, this.right) : op = _ComparisonOperator.equal;
}

class _UnaryMinus<DT, ST extends SqlType<DT>> extends Expression<DT, ST> {
  final Expression<DT, ST> inner;

  _UnaryMinus(this.inner);

  @override
  Precedence get precedence => Precedence.unary;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('-');
    inner.writeInto(context);
  }
}

class _CastExpression<D1, D2, S1 extends SqlType<D1>, S2 extends SqlType<D2>>
    extends Expression<D2, S2> {
  final Expression<D1, S1> inner;

  _CastExpression(this.inner);

  @override
  Precedence get precedence => inner.precedence;

  @override
  bool get isLiteral => inner.isLiteral;

  @override
  void writeInto(GenerationContext context) {
    return inner.writeInto(context);
  }
}

class _FunctionCallExpression<R, S extends SqlType<R>>
    extends Expression<R, S> {
  final String functionName;
  final List<Expression> arguments;

  @override
  final Precedence precedence = Precedence.primary;

  _FunctionCallExpression(this.functionName, this.arguments);

  @override
  void writeInto(GenerationContext context) {
    context.buffer..write(functionName)..write('(');

    var first = true;
    for (final arg in arguments) {
      if (!first) {
        context.buffer.write(', ');
      }
      arg.writeInto(context);
      first = false;
    }

    context.buffer.write(')');
  }
}
