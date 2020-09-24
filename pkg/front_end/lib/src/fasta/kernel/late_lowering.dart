// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' hide MapEntry;
import 'package:kernel/core_types.dart';

import '../../base/nnbd_mode.dart';
import '../source/source_library_builder.dart';
import '../names.dart';

const String lateFieldPrefix = '_#';
const String lateIsSetSuffix = '#isSet';
const String lateLocalPrefix = '#';
const String lateLocalGetterSuffix = '#get';
const String lateLocalSetterSuffix = '#set';

/// Creates the body for the synthesized getter used to encode the lowering
/// of a late non-final field with an initializer or a late local with an
/// initializer.
///
/// Late final field needs to detect writes during initialization and therefore
/// uses [createGetterWithInitializerWithRecheck] instead. Late final locals
/// cannot have writes during initialization since they are not in scope in
/// their own initializer.
Statement createGetterWithInitializer(CoreTypes coreTypes, int fileOffset,
    String name, DartType type, Expression initializer,
    {Expression createVariableRead({bool needsPromotion}),
    Expression createVariableWrite(Expression value),
    Expression createIsSetRead(),
    Expression createIsSetWrite(Expression value),
    IsSetEncoding isSetEncoding}) {
  assert(isSetEncoding != null);
  switch (isSetEncoding) {
    case IsSetEncoding.useIsSetField:
      // Generate:
      //
      //    if (!_#isSet#field) {
      //      _#field = <init>;
      //      _#isSet#field = true
      //    }
      //    return _#field;
      return new Block(<Statement>[
        new IfStatement(
            new Not(createIsSetRead()..fileOffset = fileOffset)
              ..fileOffset = fileOffset,
            new Block(<Statement>[
              new ExpressionStatement(
                  createVariableWrite(initializer)..fileOffset = fileOffset)
                ..fileOffset = fileOffset,
              new ExpressionStatement(
                  createIsSetWrite(
                      new BoolLiteral(true)..fileOffset = fileOffset)
                    ..fileOffset = fileOffset)
                ..fileOffset = fileOffset,
            ]),
            null)
          ..fileOffset = fileOffset,
        new ReturnStatement(
            // If [type] is a type variable with undetermined nullability we
            // need to create a read of the field that is promoted to the type
            // variable type.
            createVariableRead(needsPromotion: type.isPotentiallyNonNullable))
          ..fileOffset = fileOffset
      ])
        ..fileOffset = fileOffset;
    case IsSetEncoding.useSentinel:
      // Generate:
      //
      //    return let # = _#field in isSentinel(#) ? _#field = <init> : #;
      VariableDeclaration variable = new VariableDeclaration.forValue(
          createVariableRead(needsPromotion: false)..fileOffset = fileOffset,
          type: type.withDeclaredNullability(Nullability.nullable))
        ..fileOffset = fileOffset;
      return new ReturnStatement(
          new Let(
              variable,
              new ConditionalExpression(
                  new StaticInvocation(
                      coreTypes.isSentinelMethod,
                      new Arguments(<Expression>[
                        new VariableGet(variable)..fileOffset = fileOffset
                      ])
                        ..fileOffset = fileOffset)
                    ..fileOffset = fileOffset,
                  createVariableWrite(initializer)..fileOffset = fileOffset,
                  new VariableGet(variable, type)..fileOffset = fileOffset,
                  type)
                ..fileOffset = fileOffset)
            ..fileOffset = fileOffset)
        ..fileOffset = fileOffset;
    case IsSetEncoding.useNull:
      // Generate:
      //
      //    return let # = _#field in # == null ? _#field = <init> : #;
      VariableDeclaration variable = new VariableDeclaration.forValue(
          createVariableRead(needsPromotion: false)..fileOffset = fileOffset,
          type: type.withDeclaredNullability(Nullability.nullable))
        ..fileOffset = fileOffset;
      return new ReturnStatement(
          new Let(
              variable,
              new ConditionalExpression(
                  new MethodInvocation(
                      new VariableGet(variable)..fileOffset = fileOffset,
                      equalsName,
                      new Arguments(<Expression>[
                        new NullLiteral()..fileOffset = fileOffset
                      ])
                        ..fileOffset = fileOffset)
                    ..fileOffset = fileOffset,
                  createVariableWrite(initializer)..fileOffset = fileOffset,
                  new VariableGet(variable, type)..fileOffset = fileOffset,
                  type)
                ..fileOffset = fileOffset)
            ..fileOffset = fileOffset)
        ..fileOffset = fileOffset;
  }
  throw new UnsupportedError("Unexpected IsSetEncoding $isSetEncoding");
}

/// Creates the body for the synthesized getter used to encode the lowering
/// of a late final field with an initializer.
///
/// A late final field needs to detect writes during initialization for
/// which a `LateInitializationError` should be thrown. Late final locals
/// cannot have writes during initialization since they are not in scope in
/// their own initializer.
Statement createGetterWithInitializerWithRecheck(
    CoreTypes coreTypes,
    int fileOffset,
    String name,
    DartType type,
    String variableKindName,
    Expression initializer,
    {Expression createVariableRead({bool needsPromotion}),
    Expression createVariableWrite(Expression value),
    Expression createIsSetRead(),
    Expression createIsSetWrite(Expression value),
    IsSetEncoding isSetEncoding}) {
  Expression exception = new Throw(new ConstructorInvocation(
      coreTypes.lateInitializationErrorConstructor,
      new Arguments(<Expression>[
        new StringLiteral(
            "$variableKindName '${name}' has been assigned during "
            "initialization.")
          ..fileOffset = fileOffset
      ])
        ..fileOffset = fileOffset)
    ..fileOffset = fileOffset)
    ..fileOffset = fileOffset;
  VariableDeclaration temp =
      new VariableDeclaration.forValue(initializer, type: type)
        ..fileOffset = fileOffset;
  switch (isSetEncoding) {
    case IsSetEncoding.useIsSetField:
      // Generate:
      //
      //    if (!_#isSet#field) {
      //      var temp = <init>;
      //      if (_#isSet#field) throw '...'
      //      _#field = temp;
      //      _#isSet#field = true
      //    }
      //    return _#field;
      return new Block(<Statement>[
        new IfStatement(
            new Not(createIsSetRead()..fileOffset = fileOffset)
              ..fileOffset = fileOffset,
            new Block(<Statement>[
              temp,
              new IfStatement(
                  createIsSetRead()..fileOffset = fileOffset,
                  new ExpressionStatement(exception)..fileOffset = fileOffset,
                  null)
                ..fileOffset = fileOffset,
              new ExpressionStatement(
                  createVariableWrite(
                      new VariableGet(temp)..fileOffset = fileOffset)
                    ..fileOffset = fileOffset)
                ..fileOffset = fileOffset,
              new ExpressionStatement(
                  createIsSetWrite(
                      new BoolLiteral(true)..fileOffset = fileOffset)
                    ..fileOffset = fileOffset)
                ..fileOffset = fileOffset,
            ]),
            null)
          ..fileOffset = fileOffset,
        new ReturnStatement(
            // If [type] is a type variable with undetermined nullability we
            // need to create a read of the field that is promoted to the type
            // variable type.
            createVariableRead(needsPromotion: type.isPotentiallyNonNullable))
          ..fileOffset = fileOffset
      ])
        ..fileOffset = fileOffset;
    case IsSetEncoding.useSentinel:
      // Generate:
      //
      //    return let #1 = _#field in isSentinel(#1)
      //        ? let #2 = <init> in isSentinel(_#field)
      //            ? _#field = #2 : throw '...'
      //        : #1;
      VariableDeclaration variable = new VariableDeclaration.forValue(
          createVariableRead(needsPromotion: false)..fileOffset = fileOffset,
          type: type)
        ..fileOffset = fileOffset;
      return new ReturnStatement(
          new Let(
              variable,
              new ConditionalExpression(
                  new StaticInvocation(
                      coreTypes.isSentinelMethod,
                      new Arguments(<Expression>[
                        new VariableGet(variable)..fileOffset = fileOffset
                      ])
                        ..fileOffset = fileOffset)
                    ..fileOffset = fileOffset,
                  new Let(
                      temp,
                      new ConditionalExpression(
                          new StaticInvocation(
                              coreTypes.isSentinelMethod,
                              new Arguments(<Expression>[
                                createVariableRead(needsPromotion: false)
                                  ..fileOffset = fileOffset
                              ])
                                ..fileOffset = fileOffset)
                            ..fileOffset = fileOffset,
                          createVariableWrite(
                              new VariableGet(temp)..fileOffset = fileOffset)
                            ..fileOffset = fileOffset,
                          exception,
                          type)
                        ..fileOffset = fileOffset),
                  new VariableGet(variable)..fileOffset = fileOffset,
                  type)
                ..fileOffset = fileOffset)
            ..fileOffset = fileOffset)
        ..fileOffset = fileOffset;
    case IsSetEncoding.useNull:
      // Generate:
      //
      //    return let #1 = _#field in #1 == null
      //        ? let #2 = <init> in _#field == null
      //            ? _#field = #2 : throw '...'
      //        : #1;
      VariableDeclaration variable = new VariableDeclaration.forValue(
          createVariableRead(needsPromotion: false)..fileOffset = fileOffset,
          type: type.withDeclaredNullability(Nullability.nullable))
        ..fileOffset = fileOffset;
      return new ReturnStatement(
          new Let(
              variable,
              new ConditionalExpression(
                  new MethodInvocation(
                      new VariableGet(variable)..fileOffset = fileOffset,
                      equalsName,
                      new Arguments(<Expression>[
                        new NullLiteral()..fileOffset = fileOffset
                      ])
                        ..fileOffset = fileOffset)
                    ..fileOffset = fileOffset,
                  new Let(
                      temp,
                      new ConditionalExpression(
                          new MethodInvocation(
                              createVariableRead(needsPromotion: false)
                                ..fileOffset = fileOffset,
                              equalsName,
                              new Arguments(<Expression>[
                                new NullLiteral()..fileOffset = fileOffset
                              ])
                                ..fileOffset = fileOffset)
                            ..fileOffset = fileOffset,
                          createVariableWrite(
                              new VariableGet(temp)..fileOffset = fileOffset)
                            ..fileOffset = fileOffset,
                          exception,
                          type)
                        ..fileOffset = fileOffset),
                  new VariableGet(variable, type)..fileOffset = fileOffset,
                  type)
                ..fileOffset = fileOffset)
            ..fileOffset = fileOffset)
        ..fileOffset = fileOffset;
  }
  throw new UnsupportedError("Unexpected IsSetEncoding $isSetEncoding");
}

/// Creates the body for the synthesized getter used to encode the lowering
/// of a late field or local without an initializer.
Statement createGetterBodyWithoutInitializer(CoreTypes coreTypes,
    int fileOffset, String name, DartType type, String variableKindName,
    {Expression createVariableRead({bool needsPromotion}),
    Expression createIsSetRead(),
    IsSetEncoding isSetEncoding}) {
  assert(isSetEncoding != null);
  Expression exception = new Throw(new ConstructorInvocation(
      coreTypes.lateInitializationErrorConstructor,
      new Arguments(<Expression>[
        new StringLiteral(
            "$variableKindName '${name}' has not been initialized.")
          ..fileOffset = fileOffset
      ])
        ..fileOffset = fileOffset)
    ..fileOffset = fileOffset)
    ..fileOffset = fileOffset;
  switch (isSetEncoding) {
    case IsSetEncoding.useIsSetField:
      // Generate:
      //
      //    return _#isSet#field ? _#field : throw '...';
      return new ReturnStatement(
          new ConditionalExpression(
              createIsSetRead()..fileOffset = fileOffset,
              createVariableRead(needsPromotion: type.isPotentiallyNonNullable)
                ..fileOffset = fileOffset,
              exception,
              type)
            ..fileOffset = fileOffset)
        ..fileOffset = fileOffset;
    case IsSetEncoding.useSentinel:
      // Generate:
      //
      //    return let # = _#field in isSentinel(#) ? throw '...' : #;
      VariableDeclaration variable = new VariableDeclaration.forValue(
          createVariableRead()..fileOffset = fileOffset,
          type: type.withDeclaredNullability(Nullability.nullable))
        ..fileOffset = fileOffset;
      return new ReturnStatement(
          new Let(
              variable,
              new ConditionalExpression(
                  new StaticInvocation(
                      coreTypes.isSentinelMethod,
                      new Arguments(<Expression>[
                        new VariableGet(variable)..fileOffset = fileOffset
                      ])
                        ..fileOffset = fileOffset)
                    ..fileOffset = fileOffset,
                  exception,
                  new VariableGet(variable, type)..fileOffset = fileOffset,
                  type)
                ..fileOffset = fileOffset)
            ..fileOffset = fileOffset)
        ..fileOffset = fileOffset;
    case IsSetEncoding.useNull:
      // Generate:
      //
      //    return let # = _#field in # == null ? throw '...' : #;
      VariableDeclaration variable = new VariableDeclaration.forValue(
          createVariableRead()..fileOffset = fileOffset,
          type: type.withDeclaredNullability(Nullability.nullable))
        ..fileOffset = fileOffset;
      return new ReturnStatement(
          new Let(
              variable,
              new ConditionalExpression(
                  new MethodInvocation(
                      new VariableGet(variable)..fileOffset = fileOffset,
                      equalsName,
                      new Arguments(<Expression>[
                        new NullLiteral()..fileOffset = fileOffset
                      ])
                        ..fileOffset = fileOffset)
                    ..fileOffset = fileOffset,
                  exception,
                  new VariableGet(variable, type)..fileOffset = fileOffset,
                  type)
                ..fileOffset = fileOffset)
            ..fileOffset = fileOffset)
        ..fileOffset = fileOffset;
  }
  throw new UnsupportedError("Unexpected IsSetEncoding $isSetEncoding");
}

/// Creates the body for the synthesized setter used to encode the lowering
/// of a non-final late field or local.
Statement createSetterBody(CoreTypes coreTypes, int fileOffset, String name,
    VariableDeclaration parameter, DartType type,
    {bool shouldReturnValue,
    Expression createVariableWrite(Expression value),
    Expression createIsSetWrite(Expression value),
    IsSetEncoding isSetEncoding}) {
  assert(isSetEncoding != null);
  Statement createReturn(Expression value) {
    if (shouldReturnValue) {
      return new ReturnStatement(value)..fileOffset = fileOffset;
    } else {
      return new ExpressionStatement(value)..fileOffset = fileOffset;
    }
  }

  Statement assignment = createReturn(
      createVariableWrite(new VariableGet(parameter)..fileOffset = fileOffset)
        ..fileOffset = fileOffset);

  switch (isSetEncoding) {
    case IsSetEncoding.useIsSetField:
      // Generate:
      //
      //    _#isSet#field = true;
      //    return _#field = parameter
      //
      return new Block([
        new ExpressionStatement(
            createIsSetWrite(new BoolLiteral(true)..fileOffset = fileOffset)
              ..fileOffset = fileOffset)
          ..fileOffset = fileOffset,
        assignment
      ])
        ..fileOffset = fileOffset;
    case IsSetEncoding.useSentinel:
    case IsSetEncoding.useNull:
      // Generate:
      //
      //    return _#field = parameter
      //
      return assignment;
  }
  throw new UnsupportedError("Unexpected IsSetEncoding $isSetEncoding");
}

/// Creates the body for the synthesized setter used to encode the lowering
/// of a final late field or local.
Statement createSetterBodyFinal(
    CoreTypes coreTypes,
    int fileOffset,
    String name,
    VariableDeclaration parameter,
    DartType type,
    String variableKindName,
    {bool shouldReturnValue,
    Expression createVariableRead(),
    Expression createVariableWrite(Expression value),
    Expression createIsSetRead(),
    Expression createIsSetWrite(Expression value),
    IsSetEncoding isSetEncoding}) {
  assert(isSetEncoding != null);
  Expression exception = new Throw(new ConstructorInvocation(
      coreTypes.lateInitializationErrorConstructor,
      new Arguments(<Expression>[
        new StringLiteral(
            "${variableKindName} '${name}' has already been initialized.")
          ..fileOffset = fileOffset
      ])
        ..fileOffset = fileOffset)
    ..fileOffset = fileOffset)
    ..fileOffset = fileOffset;

  Statement createReturn(Expression value) {
    if (shouldReturnValue) {
      return new ReturnStatement(value)..fileOffset = fileOffset;
    } else {
      return new ExpressionStatement(value)..fileOffset = fileOffset;
    }
  }

  switch (isSetEncoding) {
    case IsSetEncoding.useIsSetField:
      // Generate:
      //
      //    if (_#isSet#field) {
      //      throw '...';
      //    } else
      //      _#isSet#field = true;
      //      return _#field = parameter
      //    }
      return new IfStatement(
          createIsSetRead()..fileOffset = fileOffset,
          new ExpressionStatement(exception)..fileOffset = fileOffset,
          new Block([
            new ExpressionStatement(
                createIsSetWrite(new BoolLiteral(true)..fileOffset = fileOffset)
                  ..fileOffset = fileOffset)
              ..fileOffset = fileOffset,
            createReturn(createVariableWrite(
                new VariableGet(parameter)..fileOffset = fileOffset)
              ..fileOffset = fileOffset)
          ])
            ..fileOffset = fileOffset)
        ..fileOffset = fileOffset;
    case IsSetEncoding.useSentinel:
      // Generate:
      //
      //    if (isSentinel(_#field)) {
      //      return _#field = parameter;
      //    } else {
      //      throw '...';
      //    }
      return new IfStatement(
        new StaticInvocation(
            coreTypes.isSentinelMethod,
            new Arguments(
                <Expression>[createVariableRead()..fileOffset = fileOffset])
              ..fileOffset = fileOffset)
          ..fileOffset = fileOffset,
        createReturn(createVariableWrite(
            new VariableGet(parameter)..fileOffset = fileOffset)
          ..fileOffset = fileOffset),
        new ExpressionStatement(exception)..fileOffset = fileOffset,
      )..fileOffset = fileOffset;
    case IsSetEncoding.useNull:
      // Generate:
      //
      //    if (_#field == null) {
      //      return _#field = parameter;
      //    } else {
      //      throw '...';
      //    }
      return new IfStatement(
        new MethodInvocation(
            createVariableRead()..fileOffset = fileOffset,
            equalsName,
            new Arguments(
                <Expression>[new NullLiteral()..fileOffset = fileOffset])
              ..fileOffset = fileOffset)
          ..fileOffset = fileOffset,
        createReturn(createVariableWrite(
            new VariableGet(parameter)..fileOffset = fileOffset)
          ..fileOffset = fileOffset),
        new ExpressionStatement(exception)..fileOffset = fileOffset,
      )..fileOffset = fileOffset;
  }
  throw new UnsupportedError("Unexpected IsSetEncoding $isSetEncoding");
}

/// Strategies for encoding whether a late field/local has been initialized.
enum IsSetEncoding {
  /// Use a boolean `isSet` field/local.
  useIsSetField,

  /// Use `null` as sentinel value to signal an uninitialized field/locals.
  useNull,

  /// Use `createSentinel`and `isSentinel` from `dart:_internal` to generate
  /// and check a sentinel value to signal an uninitialized field/local.
  useSentinel,
}

/// Strategies for encoding of late fields and locals.
enum IsSetStrategy {
  /// Always is use an `isSet` field/local to track whether the field/local has
  /// been initialized.
  forceUseIsSetField,

  /// For potentially nullable fields/locals use an `isSet` field/local to track
  /// whether the field/local has been initialized. Otherwise use `null` as
  /// sentinel value to signal an uninitialized field/local.
  ///
  /// This strategy can only be used with sound null safety mode. In weak mode
  /// non-nullable can be assigned `null` from legacy code and therefore `null`
  /// doesn't work as a sentinel.
  useIsSetFieldOrNull,

  /// For potentially nullable fields/locals use `createSentinel`and
  /// `isSentinel` from `dart:_internal` to generate and check a sentinel value
  /// to signal an uninitialized field/local. Otherwise use `null` as
  /// sentinel value to signal an uninitialized field/local.
  useSentinelOrNull,
}

IsSetStrategy computeIsSetStrategy(SourceLibraryBuilder libraryBuilder) {
  IsSetStrategy isSetStrategy = IsSetStrategy.useIsSetFieldOrNull;
  if (libraryBuilder.loader.target.backendTarget.supportsLateLoweringSentinel) {
    isSetStrategy = IsSetStrategy.useSentinelOrNull;
  } else if (libraryBuilder.loader.nnbdMode != NnbdMode.Strong) {
    isSetStrategy = IsSetStrategy.forceUseIsSetField;
  }
  return isSetStrategy;
}

IsSetEncoding computeIsSetEncoding(DartType type, IsSetStrategy isSetStrategy) {
  switch (isSetStrategy) {
    case IsSetStrategy.forceUseIsSetField:
      return IsSetEncoding.useIsSetField;
    case IsSetStrategy.useIsSetFieldOrNull:
      return type.isPotentiallyNullable
          ? IsSetEncoding.useIsSetField
          : IsSetEncoding.useNull;
    case IsSetStrategy.useSentinelOrNull:
      return type.isPotentiallyNullable
          ? IsSetEncoding.useSentinel
          : IsSetEncoding.useNull;
  }
  throw new UnsupportedError("Unexpected IsSetStrategy $isSetStrategy");
}
