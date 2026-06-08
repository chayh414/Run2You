// lib/services/health_services.dart
import 'package:health/health.dart';

/// 서버에 보낼 헬스 요약 데이터 구조
class HealthSummary {
  final double avgHeartRate;
  final double maxHeartRate;
  final double totalCalories;

  HealthSummary({
    required this.avgHeartRate,
    required this.maxHeartRate,
    required this.totalCalories,
  });
}

/// 읽어올 데이터 타입들 (심박수 + 활동 칼로리)
final List<HealthDataType> healthDataTypes = [
  HealthDataType.HEART_RATE,
  HealthDataType.ACTIVE_ENERGY_BURNED,
];

/// health 패키지의 글로벌 싱글톤 인스턴스
/// (v10부터는 HealthFactory 대신 Health() 싱글톤을 쓰는 방식으로 바뀜) :contentReference[oaicite:3]{index=3}
final Health _health = Health();

/// 헬스 데이터 읽기 권한 요청
Future<bool> requestHealthPermissions() async {
  // 각 타입에 대해 READ 권한만 요청
  final List<HealthDataAccess> permissions = List.generate(
    healthDataTypes.length,
    (_) => HealthDataAccess.READ,
  );

  // 이미 권한이 있는지 먼저 확인
  final hasPerm = await _health.hasPermissions(
        healthDataTypes,
        permissions: permissions,
      ) ??
      false;

  if (hasPerm) return true;

  // 없으면 requestAuthorization
  final granted = await _health.requestAuthorization(
    healthDataTypes,
    permissions: permissions,
  );

  return granted;
}

/// 특정 기간(startTime ~ endTime)의 헬스 데이터를 조회하고
/// 평균 심박수 / 최대 심박수 / 총 칼로리를 계산해서 반환
Future<HealthSummary> getAndCalculateHealthData(
  DateTime startTime,
  DateTime endTime,
) async {
  // 1. 데이터 조회
  final List<HealthDataPoint> rawData =
      await _health.getHealthDataFromTypes(
    types: healthDataTypes,
    startTime: startTime,
    endTime: endTime,
  );

  // 2. 중복 제거 (static 메서드 사용)
  final List<HealthDataPoint> healthData =
      _health.removeDuplicates(rawData);

  // 3. 집계에 사용할 변수
  final List<double> heartRates = [];
  double totalCalories = 0.0;
  double maxHeartRate = 0.0;

  for (final point in healthData) {
    // 값이 숫자 타입인지 확인 (NumericHealthValue)
    if (point.value is! NumericHealthValue) continue;

    final NumericHealthValue numeric = point.value as NumericHealthValue;
    final double value = numeric.numericValue.toDouble();

    if (point.type == HealthDataType.HEART_RATE) {
      // 심박수 데이터
      heartRates.add(value);
      if (value > maxHeartRate) {
        maxHeartRate = value;
      }
    } else if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
      // 활동 칼로리 데이터
      totalCalories += value;
    }
  }

  // 4. 평균 심박수 계산
  final double avgHeartRate = heartRates.isNotEmpty
      ? heartRates.reduce((a, b) => a + b) / heartRates.length
      : 0.0;

  // 5. 소수점 1자리까지 반올림해서 정리
  return HealthSummary(
    avgHeartRate: double.parse(avgHeartRate.toStringAsFixed(1)),
    maxHeartRate: double.parse(maxHeartRate.toStringAsFixed(1)),
    totalCalories: double.parse(totalCalories.toStringAsFixed(1)),
  );
}
