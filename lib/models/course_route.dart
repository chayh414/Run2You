// lib/models/course_route.dart

/// 🔹 Flutter 쪽에서 쓸 나만의 LatLng (카카오맵 JS랑 주고받을 때 사용)
class LatLng {
  final double lat;
  final double lng;

  LatLng({
    required this.lat,
    required this.lng,
  });

  factory LatLng.fromJson(Map<String, dynamic> json) {
    return LatLng(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
    };
  }
}

/// 🔹 턴(회전) 안내 정보
class TurnInfo {
  final String type;         // "right" / "left" / "straight" ...
  final String instruction;  // "61m 앞에서 우회전"
  final double atDistM;      // 61.0  (JSON이 60.6 이런 실수라서 double로 받기)

  TurnInfo({
    required this.type,
    required this.instruction,
    required this.atDistM,
  });

  factory TurnInfo.fromJson(Map<String, dynamic> json) {
    return TurnInfo(
      type: json['type'] as String,
      instruction: json['instruction'] as String,
      atDistM: (json['at_dist_m'] as num).toDouble(),
    );
  }
}

/// 🔹 전체 코스 정보 (시작점 + polyline + 턴 리스트)
class CourseRoute {
  final LatLng start;
  final List<LatLng> polyline;
  final List<TurnInfo> turns;

  CourseRoute({
    required this.start,
    required this.polyline,
    required this.turns,
  });

  factory CourseRoute.fromJson(Map<String, dynamic> json) {
    final startJson = json['start'] as Map<String, dynamic>;
    final polylineJson = json['polyline'] as List;
    final turnsJson = json['turns'] as List;

    return CourseRoute(
      start: LatLng.fromJson(startJson),
      polyline: polylineJson
          .map((p) => LatLng.fromJson(p as Map<String, dynamic>))
          .toList(),
      turns: turnsJson
          .map((t) => TurnInfo.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}