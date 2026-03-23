// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

CookingSession _$CookingSessionFromJson(Map<String, dynamic> json) {
  return _CookingSession.fromJson(json);
}

/// @nodoc
mixin _$CookingSession {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'user_id')
  String get userId => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  @JsonKey(name: 'recipe_ids')
  List<String> get recipeIds => throw _privateConstructorUsedError;
  List<SessionStep> get steps => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime? get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'started_at')
  DateTime? get startedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt => throw _privateConstructorUsedError;

  /// Serializes this CookingSession to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CookingSession
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CookingSessionCopyWith<CookingSession> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CookingSessionCopyWith<$Res> {
  factory $CookingSessionCopyWith(
    CookingSession value,
    $Res Function(CookingSession) then,
  ) = _$CookingSessionCopyWithImpl<$Res, CookingSession>;
  @useResult
  $Res call({
    String id,
    @JsonKey(name: 'user_id') String userId,
    String status,
    @JsonKey(name: 'recipe_ids') List<String> recipeIds,
    List<SessionStep> steps,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
  });
}

/// @nodoc
class _$CookingSessionCopyWithImpl<$Res, $Val extends CookingSession>
    implements $CookingSessionCopyWith<$Res> {
  _$CookingSessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CookingSession
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? status = null,
    Object? recipeIds = null,
    Object? steps = null,
    Object? createdAt = freezed,
    Object? startedAt = freezed,
    Object? completedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            userId: null == userId
                ? _value.userId
                : userId // ignore: cast_nullable_to_non_nullable
                      as String,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            recipeIds: null == recipeIds
                ? _value.recipeIds
                : recipeIds // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            steps: null == steps
                ? _value.steps
                : steps // ignore: cast_nullable_to_non_nullable
                      as List<SessionStep>,
            createdAt: freezed == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            startedAt: freezed == startedAt
                ? _value.startedAt
                : startedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            completedAt: freezed == completedAt
                ? _value.completedAt
                : completedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$CookingSessionImplCopyWith<$Res>
    implements $CookingSessionCopyWith<$Res> {
  factory _$$CookingSessionImplCopyWith(
    _$CookingSessionImpl value,
    $Res Function(_$CookingSessionImpl) then,
  ) = __$$CookingSessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    @JsonKey(name: 'user_id') String userId,
    String status,
    @JsonKey(name: 'recipe_ids') List<String> recipeIds,
    List<SessionStep> steps,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
  });
}

/// @nodoc
class __$$CookingSessionImplCopyWithImpl<$Res>
    extends _$CookingSessionCopyWithImpl<$Res, _$CookingSessionImpl>
    implements _$$CookingSessionImplCopyWith<$Res> {
  __$$CookingSessionImplCopyWithImpl(
    _$CookingSessionImpl _value,
    $Res Function(_$CookingSessionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CookingSession
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? status = null,
    Object? recipeIds = null,
    Object? steps = null,
    Object? createdAt = freezed,
    Object? startedAt = freezed,
    Object? completedAt = freezed,
  }) {
    return _then(
      _$CookingSessionImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        userId: null == userId
            ? _value.userId
            : userId // ignore: cast_nullable_to_non_nullable
                  as String,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        recipeIds: null == recipeIds
            ? _value._recipeIds
            : recipeIds // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        steps: null == steps
            ? _value._steps
            : steps // ignore: cast_nullable_to_non_nullable
                  as List<SessionStep>,
        createdAt: freezed == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        startedAt: freezed == startedAt
            ? _value.startedAt
            : startedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        completedAt: freezed == completedAt
            ? _value.completedAt
            : completedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$CookingSessionImpl implements _CookingSession {
  const _$CookingSessionImpl({
    required this.id,
    @JsonKey(name: 'user_id') required this.userId,
    required this.status,
    @JsonKey(name: 'recipe_ids') final List<String> recipeIds = const [],
    final List<SessionStep> steps = const [],
    @JsonKey(name: 'created_at') this.createdAt,
    @JsonKey(name: 'started_at') this.startedAt,
    @JsonKey(name: 'completed_at') this.completedAt,
  }) : _recipeIds = recipeIds,
       _steps = steps;

  factory _$CookingSessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$CookingSessionImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'user_id')
  final String userId;
  @override
  final String status;
  final List<String> _recipeIds;
  @override
  @JsonKey(name: 'recipe_ids')
  List<String> get recipeIds {
    if (_recipeIds is EqualUnmodifiableListView) return _recipeIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_recipeIds);
  }

  final List<SessionStep> _steps;
  @override
  @JsonKey()
  List<SessionStep> get steps {
    if (_steps is EqualUnmodifiableListView) return _steps;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_steps);
  }

  @override
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @override
  @JsonKey(name: 'started_at')
  final DateTime? startedAt;
  @override
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;

  @override
  String toString() {
    return 'CookingSession(id: $id, userId: $userId, status: $status, recipeIds: $recipeIds, steps: $steps, createdAt: $createdAt, startedAt: $startedAt, completedAt: $completedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CookingSessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.status, status) || other.status == status) &&
            const DeepCollectionEquality().equals(
              other._recipeIds,
              _recipeIds,
            ) &&
            const DeepCollectionEquality().equals(other._steps, _steps) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.startedAt, startedAt) ||
                other.startedAt == startedAt) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    userId,
    status,
    const DeepCollectionEquality().hash(_recipeIds),
    const DeepCollectionEquality().hash(_steps),
    createdAt,
    startedAt,
    completedAt,
  );

  /// Create a copy of CookingSession
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CookingSessionImplCopyWith<_$CookingSessionImpl> get copyWith =>
      __$$CookingSessionImplCopyWithImpl<_$CookingSessionImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$CookingSessionImplToJson(this);
  }
}

abstract class _CookingSession implements CookingSession {
  const factory _CookingSession({
    required final String id,
    @JsonKey(name: 'user_id') required final String userId,
    required final String status,
    @JsonKey(name: 'recipe_ids') final List<String> recipeIds,
    final List<SessionStep> steps,
    @JsonKey(name: 'created_at') final DateTime? createdAt,
    @JsonKey(name: 'started_at') final DateTime? startedAt,
    @JsonKey(name: 'completed_at') final DateTime? completedAt,
  }) = _$CookingSessionImpl;

  factory _CookingSession.fromJson(Map<String, dynamic> json) =
      _$CookingSessionImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'user_id')
  String get userId;
  @override
  String get status;
  @override
  @JsonKey(name: 'recipe_ids')
  List<String> get recipeIds;
  @override
  List<SessionStep> get steps;
  @override
  @JsonKey(name: 'created_at')
  DateTime? get createdAt;
  @override
  @JsonKey(name: 'started_at')
  DateTime? get startedAt;
  @override
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt;

  /// Create a copy of CookingSession
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CookingSessionImplCopyWith<_$CookingSessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SessionStep _$SessionStepFromJson(Map<String, dynamic> json) {
  return _SessionStep.fromJson(json);
}

/// @nodoc
mixin _$SessionStep {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'order_index')
  int get orderIndex => throw _privateConstructorUsedError;
  String get text => throw _privateConstructorUsedError;
  @JsonKey(name: 'source_dish_tag')
  String? get sourceDishTag => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_completed')
  bool get isCompleted => throw _privateConstructorUsedError;
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'agent_notes')
  String? get agentNotes => throw _privateConstructorUsedError;

  /// Serializes this SessionStep to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SessionStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionStepCopyWith<SessionStep> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionStepCopyWith<$Res> {
  factory $SessionStepCopyWith(
    SessionStep value,
    $Res Function(SessionStep) then,
  ) = _$SessionStepCopyWithImpl<$Res, SessionStep>;
  @useResult
  $Res call({
    String id,
    @JsonKey(name: 'order_index') int orderIndex,
    String text,
    @JsonKey(name: 'source_dish_tag') String? sourceDishTag,
    @JsonKey(name: 'is_completed') bool isCompleted,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'agent_notes') String? agentNotes,
  });
}

/// @nodoc
class _$SessionStepCopyWithImpl<$Res, $Val extends SessionStep>
    implements $SessionStepCopyWith<$Res> {
  _$SessionStepCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SessionStep
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? orderIndex = null,
    Object? text = null,
    Object? sourceDishTag = freezed,
    Object? isCompleted = null,
    Object? completedAt = freezed,
    Object? agentNotes = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            orderIndex: null == orderIndex
                ? _value.orderIndex
                : orderIndex // ignore: cast_nullable_to_non_nullable
                      as int,
            text: null == text
                ? _value.text
                : text // ignore: cast_nullable_to_non_nullable
                      as String,
            sourceDishTag: freezed == sourceDishTag
                ? _value.sourceDishTag
                : sourceDishTag // ignore: cast_nullable_to_non_nullable
                      as String?,
            isCompleted: null == isCompleted
                ? _value.isCompleted
                : isCompleted // ignore: cast_nullable_to_non_nullable
                      as bool,
            completedAt: freezed == completedAt
                ? _value.completedAt
                : completedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            agentNotes: freezed == agentNotes
                ? _value.agentNotes
                : agentNotes // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SessionStepImplCopyWith<$Res>
    implements $SessionStepCopyWith<$Res> {
  factory _$$SessionStepImplCopyWith(
    _$SessionStepImpl value,
    $Res Function(_$SessionStepImpl) then,
  ) = __$$SessionStepImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    @JsonKey(name: 'order_index') int orderIndex,
    String text,
    @JsonKey(name: 'source_dish_tag') String? sourceDishTag,
    @JsonKey(name: 'is_completed') bool isCompleted,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'agent_notes') String? agentNotes,
  });
}

/// @nodoc
class __$$SessionStepImplCopyWithImpl<$Res>
    extends _$SessionStepCopyWithImpl<$Res, _$SessionStepImpl>
    implements _$$SessionStepImplCopyWith<$Res> {
  __$$SessionStepImplCopyWithImpl(
    _$SessionStepImpl _value,
    $Res Function(_$SessionStepImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SessionStep
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? orderIndex = null,
    Object? text = null,
    Object? sourceDishTag = freezed,
    Object? isCompleted = null,
    Object? completedAt = freezed,
    Object? agentNotes = freezed,
  }) {
    return _then(
      _$SessionStepImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        orderIndex: null == orderIndex
            ? _value.orderIndex
            : orderIndex // ignore: cast_nullable_to_non_nullable
                  as int,
        text: null == text
            ? _value.text
            : text // ignore: cast_nullable_to_non_nullable
                  as String,
        sourceDishTag: freezed == sourceDishTag
            ? _value.sourceDishTag
            : sourceDishTag // ignore: cast_nullable_to_non_nullable
                  as String?,
        isCompleted: null == isCompleted
            ? _value.isCompleted
            : isCompleted // ignore: cast_nullable_to_non_nullable
                  as bool,
        completedAt: freezed == completedAt
            ? _value.completedAt
            : completedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        agentNotes: freezed == agentNotes
            ? _value.agentNotes
            : agentNotes // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SessionStepImpl implements _SessionStep {
  const _$SessionStepImpl({
    required this.id,
    @JsonKey(name: 'order_index') required this.orderIndex,
    required this.text,
    @JsonKey(name: 'source_dish_tag') this.sourceDishTag,
    @JsonKey(name: 'is_completed') this.isCompleted = false,
    @JsonKey(name: 'completed_at') this.completedAt,
    @JsonKey(name: 'agent_notes') this.agentNotes,
  });

  factory _$SessionStepImpl.fromJson(Map<String, dynamic> json) =>
      _$$SessionStepImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'order_index')
  final int orderIndex;
  @override
  final String text;
  @override
  @JsonKey(name: 'source_dish_tag')
  final String? sourceDishTag;
  @override
  @JsonKey(name: 'is_completed')
  final bool isCompleted;
  @override
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;
  @override
  @JsonKey(name: 'agent_notes')
  final String? agentNotes;

  @override
  String toString() {
    return 'SessionStep(id: $id, orderIndex: $orderIndex, text: $text, sourceDishTag: $sourceDishTag, isCompleted: $isCompleted, completedAt: $completedAt, agentNotes: $agentNotes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionStepImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.orderIndex, orderIndex) ||
                other.orderIndex == orderIndex) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.sourceDishTag, sourceDishTag) ||
                other.sourceDishTag == sourceDishTag) &&
            (identical(other.isCompleted, isCompleted) ||
                other.isCompleted == isCompleted) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt) &&
            (identical(other.agentNotes, agentNotes) ||
                other.agentNotes == agentNotes));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    orderIndex,
    text,
    sourceDishTag,
    isCompleted,
    completedAt,
    agentNotes,
  );

  /// Create a copy of SessionStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionStepImplCopyWith<_$SessionStepImpl> get copyWith =>
      __$$SessionStepImplCopyWithImpl<_$SessionStepImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SessionStepImplToJson(this);
  }
}

abstract class _SessionStep implements SessionStep {
  const factory _SessionStep({
    required final String id,
    @JsonKey(name: 'order_index') required final int orderIndex,
    required final String text,
    @JsonKey(name: 'source_dish_tag') final String? sourceDishTag,
    @JsonKey(name: 'is_completed') final bool isCompleted,
    @JsonKey(name: 'completed_at') final DateTime? completedAt,
    @JsonKey(name: 'agent_notes') final String? agentNotes,
  }) = _$SessionStepImpl;

  factory _SessionStep.fromJson(Map<String, dynamic> json) =
      _$SessionStepImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'order_index')
  int get orderIndex;
  @override
  String get text;
  @override
  @JsonKey(name: 'source_dish_tag')
  String? get sourceDishTag;
  @override
  @JsonKey(name: 'is_completed')
  bool get isCompleted;
  @override
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt;
  @override
  @JsonKey(name: 'agent_notes')
  String? get agentNotes;

  /// Create a copy of SessionStep
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionStepImplCopyWith<_$SessionStepImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
