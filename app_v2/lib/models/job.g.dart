// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$JobImpl _$$JobImplFromJson(Map<String, dynamic> json) => _$JobImpl(
  id: json['id'] as String,
  type: json['type'] as String,
  status: json['status'] as String,
  payload: json['payload'] as Map<String, dynamic>? ?? const {},
  result: json['result'] as Map<String, dynamic>?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$$JobImplToJson(_$JobImpl instance) => <String, dynamic>{
  'id': instance.id,
  'type': instance.type,
  'status': instance.status,
  'payload': instance.payload,
  'result': instance.result,
  'created_at': instance.createdAt?.toIso8601String(),
};
