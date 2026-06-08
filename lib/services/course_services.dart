// lib/services/course_services.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;

import '../config.dart';

/// =======================================
/// 🎯 (선택) 새 AI 코스 추천 API
/// =======================================
/// 사용 안 하면 지워도 됨. 현재 HomeScreen에서는
/// /api/courses/recommend 를 직접 호출 중이라
/// 이 함수는 여유로 놔둔 상태.
Future<Map<String, dynamic>?> fetchRecommendedCourseApi({
  required int km,
  double? startLat,
  double? startLng,
  String? token,
}) async {
  final url = Uri.parse('$baseUrl/api/courses/route?km=$km');

  try {
    debugPrint('🎯 fetchRecommendedCourse url: $url');

    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
      },
    );

    debugPrint('🎯 fetchRecommendedCourse status: ${response.statusCode}');
    debugPrint('🎯 fetchRecommendedCourse response: ${response.body}');

    final decoded = response.body.isNotEmpty
        ? jsonDecode(utf8.decode(response.bodyBytes))
        : null;

    return {
      'statusCode': response.statusCode,
      'body': decoded as Map<String, dynamic>?,
    };
  } catch (e) {
    debugPrint('❌ fetchRecommendedCourseApi error: $e');
    return null;
  }
}

/// =========================
/// 🏃‍♀️ 코스 저장 API
/// =========================
/// ✅ 최신 명세:
/// POST /api/courses/start
///
/// Request: CreateCourseRequest (백엔드 정의와 동일)
/// Response:
/// {
///   "courseId": 10,
///   "status": "ok"
/// }
///
/// 🔹 여기서는 courseData(JSON) + userId로
///    body를 만들어서 코스를 저장한다.
Future<Map<String, dynamic>?> startCourseApi({
  required String token,
  required int userId,
  required Map<String, dynamic> courseData,
  required int km,
}) async {
  final url = Uri.parse('$baseUrl/api/courses/start');

  try {
    // ✅ start 좌표 추출
    final start = (courseData['start'] ?? {}) as Map;
    final polyline = (courseData['polyline'] as List?) ?? [];

    final double startLat = (start['lat'] as num).toDouble();
    final double startLng = (start['lng'] as num).toDouble();

    // ✅ 끝점은 polyline의 마지막 좌표
    double endLat = startLat;
    double endLng = startLng;
    if (polyline.isNotEmpty) {
      final last = polyline.last as Map;
      endLat = (last['lat'] as num).toDouble();
      endLng = (last['lng'] as num).toDouble();
    }

    // ✅ summary에서 거리 정보 추출
    final summary = courseData['summary'] as Map<String, dynamic>?;

    double distanceKm;
    if (summary != null && summary['length_m'] != null) {
      distanceKm = (summary['length_m'] as num).toDouble() / 1000.0;
    } else if (summary != null && summary['km_requested'] != null) {
      distanceKm = (summary['km_requested'] as num).toDouble();
    } else {
      distanceKm = km.toDouble();
    }

    // ⚠️ 여기 body 구조가 실제 CreateCourseRequest 랑 맞아야 함
    // 백엔드 DTO에 맞게 key 이름만 수정하면 됨.
    final body = {
      'userId': userId,
      'name': 'AI 추천 코스 ${distanceKm.toStringAsFixed(1)}km',
      'startLat': startLat,
      'startLng': startLng,
      'endLat': endLat,
      'endLng': endLng,
      'distanceKm': double.parse(distanceKm.toStringAsFixed(2)),
      'jsonUrl': '', // 필요없으면 백엔드에서 무시해도 됨
    };

    debugPrint('🏃‍♀️ startCourse body: $body');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    debugPrint('🏃‍♀️ startCourse status: ${response.statusCode}');
    debugPrint('🏃‍♀️ startCourse response: ${response.body}');

    final decoded = response.body.isNotEmpty
        ? jsonDecode(utf8.decode(response.bodyBytes))
        : null;

    return {
      'statusCode': response.statusCode,
      'body': decoded, // { "courseId": 10, "status": "ok" } 예상
    };
  } catch (e) {
    debugPrint('❌ startCourseApi error: $e');
    return null;
  }
}

/// =========================
/// 🆕 러닝 시작 API
/// =========================
/// POST /api/run-records/start
/// Request:
/// {
///   "userId": 1,
///   "courseId": 10
/// }
///
/// Response:
///   5  ← 생성된 recordId (숫자 그대로)
Future<Map<String, dynamic>?> startRunRecordApi({
  required String token,
  required int userId,
  required int courseId,
}) async {
  final uri = Uri.parse('$baseUrl/api/run-records/start');

  try {
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'userId': userId,
        'courseId': courseId,
      }),
    );

    final rawBody = utf8.decode(response.bodyBytes).trim();
    final recordId = int.tryParse(rawBody);

    debugPrint(
        '🏃‍♀️ startRunRecordApi status=${response.statusCode}, body="$rawBody", recordId=$recordId');

    return {
      'statusCode': response.statusCode,
      'recordId': recordId,
      'rawBody': rawBody,
    };
  } catch (e) {
    debugPrint('❌ startRunRecordApi error: $e');
    return null;
  }
}

/// =========================
/// ⏸ 러닝 일시정지 API
/// =========================
/// POST /api/run-records/{recordId}/pause
///
/// PathVariable: recordId
Future<Map<String, dynamic>?> pauseRunRecordApi({
  required String token,
  required int recordId,
}) async {
  final uri = Uri.parse('$baseUrl/api/run-records/$recordId/pause');

  try {
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      },
    );

    final rawBody = utf8.decode(response.bodyBytes);
    debugPrint(
        '⏸ pauseRunRecordApi status=${response.statusCode}, body=$rawBody');

    return {
      'statusCode': response.statusCode,
      'rawBody': rawBody,
    };
  } catch (e) {
    debugPrint('❌ pauseRunRecordApi error: $e');
    return null;
  }
}

/// =========================
/// ▶️ (가정) 러닝 재시작 API
/// =========================
/// ❗ 백엔드에서 실제 경로가 다르면
///    아래 /resume 부분만 고치면 됨.
/// 예: POST /api/run-records/{recordId}/resume
Future<Map<String, dynamic>?> resumeRunRecordApi({
  required String token,
  required int recordId,
}) async {
  final uri = Uri.parse('$baseUrl/api/run-records/$recordId/resume');

  try {
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      },
    );

    final rawBody = utf8.decode(response.bodyBytes);
    debugPrint(
        '▶️ resumeRunRecordApi status=${response.statusCode}, body=$rawBody');

    return {
      'statusCode': response.statusCode,
      'rawBody': rawBody,
    };
  } catch (e) {
    debugPrint('❌ resumeRunRecordApi error: $e');
    return null;
  }
}

/// =========================
/// ⏹ 러닝 종료 API
/// =========================
/// POST /api/run-records/{recordId}/finish
///
/// Request Body:
/// {
///   "distanceM": 3140,
///   "durationSec": 600,
///   "avgHeartRate": 120,
///   "maxHeartRate": 150,
///   "calories": 80
/// }
Future<Map<String, dynamic>?> finishRunRecordApi({
  required String token,
  required int recordId,
  required double distanceM, // 프론트는 double로 계산, 서버에는 int로 보냄
  required int durationSec,
  int? avgHeartRate,
  int? maxHeartRate,
  int? calories,
}) async {
  final uri = Uri.parse('$baseUrl/api/run-records/$recordId/finish');

  try {
    // 🔹 백엔드 DTO(FinishRunRecordRequest)에 맞춘 바디
    final Map<String, dynamic> body = {
      'distanceM': distanceM.round(), // DTO는 int라 반올림해서 보냄
      'durationSec': durationSec,
      'avgHeartRate': avgHeartRate,
      'maxHeartRate': maxHeartRate,
      'calories': calories,
    };

    // null 값은 보내지 않으려면 제거
    body.removeWhere((key, value) => value == null);

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    final rawBody = utf8.decode(response.bodyBytes);
    debugPrint(
        '⏹ finishRunRecordApi status=${response.statusCode}, body=$rawBody');

    return {
      'statusCode': response.statusCode,
      'rawBody': rawBody,
    };
  } catch (e) {
    debugPrint('❌ finishRunRecordApi error: $e');
    return null;
  }
}