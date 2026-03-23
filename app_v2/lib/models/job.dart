import 'package:freezed_annotation/freezed_annotation.dart';

part 'job.freezed.dart';
part 'job.g.dart';

@freezed
class Job with _$Job {
  const factory Job({
    required String id,
    required String type,
    required String status,
    @Default({}) Map<String, dynamic> payload,
    Map<String, dynamic>? result,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _Job;

  factory Job.fromJson(Map<String, dynamic> json) => _$JobFromJson(json);
}
