// lib/services/aws_services.dart
// 러닝 기록 서버 통신 관련 파일!

import 'dart:convert';
import 'package:http/http.dart' as http;

/// 서버 기본 URL
/// 👉 현재 백엔드에서 사용 중인 서버 주소로 변경해 둔 상태
const String baseUrl = 'http://54.253.221.244:8080';

/// 기존: 러닝 기록 POST용 엔드포인트
const String runRecordsEndpoint = '$baseUrl/api/run-records';

/// 신규: 기간별 조회용 엔드포인트 (예: /api/users/{userId}/run-records)
String userRunRecordsEndpoint(int userId) =>
    '$baseUrl/api/users/$userId/run-records';

/// ============================================================
/// 공통: JSON 숫자 파싱 헬퍼 (null / 문자열도 안전하게 처리)
/// ============================================================

int _toInt(dynamic v, {int defaultValue = 0}) {
  if (v == null) return defaultValue;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? defaultValue;
  return defaultValue;
}

double _toDouble(dynamic v, {double defaultValue = 0.0}) {
  if (v == null) return defaultValue;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? defaultValue;
  return defaultValue;
}

/// ------------------------------------------------------------
/// 1. 러닝 기록 전송 (기존 기능)
/// ------------------------------------------------------------

/// 최종 러닝 기록을 서버로 전송하는 함수
///
/// 서버에서 실제로 필요로 하는 필드 이름/형식은
/// 백엔드에서 준 명세에 맞게 body 부분을 조정해줘야 한다.
Future<bool> sendRunRecordToServer({
  required int userId,
  required double distanceKm,
  required int durationSeconds,
  required String startTimeIso,
  required String polylineData,
  required double avgHeartRate,
  required double maxHeartRate,
  required double caloriesBurned,
}) async {
  try {
    final uri = Uri.parse(runRecordsEndpoint);

    final body = {
      'user_id': userId,
      'distance_km': distanceKm,
      'duration_sec': durationSeconds,
      'started_at': startTimeIso,
      'polyline': polylineData,
      'avg_heart_rate': avgHeartRate,
      'max_heart_rate': maxHeartRate,
      'calories_burned': caloriesBurned, // ✔ 기존 네이밍 유지
    };

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    return response.statusCode == 200 || response.statusCode == 201;
  } catch (e) {
    return false;
  }
}

/// ------------------------------------------------------------
/// 2. 러닝 기록 조회용 모델들
///    (기간별 조회 API 응답 파싱용)
/// ------------------------------------------------------------

/// 개별 러닝 기록
class RunRecord {
  final int recordId;
  final int userId;
  final double distanceM;
  final int durationSec;
  final int calories;
  final int avgHeartRate;
  final int maxHeartRate;

  /// 평균 페이스 (초 단위) – 예: 5분 30초/km => 330
  final int paceSec;

  /// 평균 페이스 (문자열) – 예: "5'30\" /km"
  final String paceStr;

  final DateTime startedAt;
  final DateTime endedAt;

  RunRecord({
    required this.recordId,
    required this.userId,
    required this.distanceM,
    required this.durationSec,
    required this.calories,
    required this.avgHeartRate,
    required this.maxHeartRate,
    required this.paceSec,
    required this.paceStr,
    required this.startedAt,
    required this.endedAt,
  });

  /// ⚠️ JSON 키 이름은 실제 백엔드 응답에 맞게 수정 필요
  factory RunRecord.fromJson(Map<String, dynamic> json) {
    return RunRecord(
      // 키 이름이 record_id / recordId / id 중 뭐든 와도 어느 정도 커버
      recordId: _toInt(json['record_id'] ?? json['recordId'] ?? json['id']),
      userId: _toInt(json['user_id'] ?? json['userId']),
      distanceM: _toDouble(json['distance_m'] ?? json['distanceM']),
      durationSec: _toInt(json['duration_sec'] ?? json['durationSec']),
      calories: _toInt(json['calories']),
      avgHeartRate:
          _toInt(json['avg_heart_rate'] ?? json['avgHeartRate']),
      maxHeartRate:
          _toInt(json['max_heart_rate'] ?? json['maxHeartRate']),
      paceSec: _toInt(json['pace_sec'] ?? json['paceSec']),
      paceStr: (json['pace_str'] ?? json['paceStr'] ?? '') as String,
      startedAt: DateTime.parse(
        (json['started_at'] ?? json['startedAt']) as String,
      ),
      endedAt: DateTime.parse(
        (json['ended_at'] ?? json['endedAt']) as String,
      ),
    );
  }
}

/// 기간(월/일)에 대한 요약 정보 (summary)
class RunSummary {
  final int runCount;
  final double totalDistanceM;
  final int totalDurationSec;
  final int totalCalories;
  final double avgHeartRate;

  /// 평균 페이스 (초 단위)
  final int avgPaceSec;

  /// 평균 페이스 (문자열) – 선택적으로 내려오는 경우
  final String? avgPaceStr;

  RunSummary({
    required this.runCount,
    required this.totalDistanceM,
    required this.totalDurationSec,
    required this.totalCalories,
    required this.avgHeartRate,
    required this.avgPaceSec,
    this.avgPaceStr,
  });

  /// ⚠️ JSON 키 이름은 실제 백엔드 응답에 맞게 수정 필요
  factory RunSummary.fromJson(Map<String, dynamic> json) {
    return RunSummary(
      runCount: _toInt(json['run_count'] ?? json['runCount']),
      totalDistanceM:
          _toDouble(json['total_distance_m'] ?? json['totalDistanceM']),
      totalDurationSec:
          _toInt(json['total_duration_sec'] ?? json['totalDurationSec']),
      totalCalories:
          _toInt(json['total_calories'] ?? json['totalCalories']),
      avgHeartRate:
          _toDouble(json['avg_heart_rate'] ?? json['avgHeartRate']),
      avgPaceSec: _toInt(json['avg_pace_sec'] ?? json['avgPaceSec']),
      avgPaceStr:
          (json['avg_pace_str'] ?? json['avgPaceStr']) as String?,
    );
  }
}

/// 기간별 조회 API 전체 응답
///
/// 예시 구조:
/// {
///   "summary": { ... },
///   "records": [ { ... }, { ... } ]
/// }
class PeriodRunResponse {
  final RunSummary summary;
  final List<RunRecord> records;

  PeriodRunResponse({
    required this.summary,
    required this.records,
  });

  factory PeriodRunResponse.fromJson(Map<String, dynamic> json) {
    final recordsJson = (json['records'] ?? []) as List<dynamic>;
    final summaryJson =
        (json['summary'] ?? const <String, dynamic>{}) as Map<String, dynamic>;

    return PeriodRunResponse(
      summary: RunSummary.fromJson(summaryJson),
      records: recordsJson
          .map((e) => RunRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// ------------------------------------------------------------
/// 3. 기간별 러닝 기록 조회 함수
///    (월 통계 + 일별 기록용 공통 함수)
/// ------------------------------------------------------------

Future<PeriodRunResponse> fetchRunRecords({
  required int userId,
  required DateTime start,
  required DateTime end,
}) async {
  // yyyy-MM-dd 포맷 (toIso8601String().substring(0, 10) 사용)
  final startStr = start.toIso8601String().substring(0, 10);
  final endStr = end.toIso8601String().substring(0, 10);

  final uri = Uri.parse(
    '${userRunRecordsEndpoint(userId)}?start=$startStr&end=$endStr',
  );

  // 디버그용: 실제 호출 URL 확인
  print('[API] GET URL = $uri');

  final response = await http.get(uri);

  if (response.statusCode != 200) {
    throw Exception(
      'Failed to load run records (status: ${response.statusCode})',
    );
  }

  final Map<String, dynamic> data = jsonDecode(response.body);
  return PeriodRunResponse.fromJson(data);
}
