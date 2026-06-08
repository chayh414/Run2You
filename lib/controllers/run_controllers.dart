// lib/controllers/run_controllers.dart
import 'package:flutter/material.dart';

import '../services/health_services.dart';
import '../services/aws_services.dart';

class RunController {
  /// 러닝이 끝난 뒤 호출하는 메인 함수
  ///
  /// [userId]        : 로그인된 사용자 ID
  /// [distanceKm]    : 총 러닝 거리 (km)
  /// [startTime]     : 러닝 시작 시각
  /// [endTime]       : 러닝 종료 시각
  /// [polylineData]  : 지도에 사용될 경로(polyline) 인코딩 문자열
  Future<bool> finishRunAndSave({
    required BuildContext context,
    required int userId,
    required double distanceKm,
    required DateTime startTime,
    required DateTime endTime,
    required String polylineData,
  }) async {
    final int durationSeconds = endTime.difference(startTime).inSeconds;

    // 1) 헬스 권한 요청
    final bool isAuthorized = await requestHealthPermissions();
    if (!isAuthorized) {
      debugPrint('헬스 권한 없음 → 헬스 데이터 없이 러닝 기록만 저장');

      // 헬스 데이터 0으로 넣고 바로 저장
      return await sendRunRecordToServer(
        userId: userId,
        distanceKm: distanceKm,
        durationSeconds: durationSeconds,
        startTimeIso: startTime.toIso8601String(),
        polylineData: polylineData,
        avgHeartRate: 0,
        maxHeartRate: 0,
        caloriesBurned: 0,
      );
    }

    // 2) 헬스 데이터 조회 + 요약 계산
    final HealthSummary summary =
        await getAndCalculateHealthData(startTime, endTime);

    // 3) 서버로 최종 기록 전송
    final bool success = await sendRunRecordToServer(
      userId: userId,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
      startTimeIso: startTime.toIso8601String(),
      polylineData: polylineData,
      avgHeartRate: summary.avgHeartRate,
      maxHeartRate: summary.maxHeartRate,
      caloriesBurned: summary.totalCalories,
    );

    // 4) 간단한 UI 피드백 (필요하면 수정)
    if (!context.mounted) return success;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('러닝 기록이 저장되었습니다.')),
      );
      // TODO: 저장 후 캘린더 화면으로 이동 등 네가 원하는 처리 추가
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('러닝 기록 저장에 실패했습니다.')),
      );
    }

    return success;
  }
}
