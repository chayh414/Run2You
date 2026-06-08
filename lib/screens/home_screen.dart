// lib/screens/home_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../config.dart';
import '../widgets/r2u_app_bar.dart';
import '../services/course_services.dart';
import '../utils/run_storage.dart' as run_storage;
import 'package:shared_preferences/shared_preferences.dart';

// 🔹 코스/턴 모델
import '../models/course_route.dart';

/// 🔹 폴리라인 스냅 계산 결과
class _SnapResult {
  final double lat;
  final double lng;
  final double distanceMeter;

  const _SnapResult(this.lat, this.lng, this.distanceMeter);
}

/// 🔹 polyline 포인트에서 lat/lng 뽑는 헬퍼
double _getPointLat(dynamic p) => (p.lat as num).toDouble();
double _getPointLng(dynamic p) => (p.lng as num).toDouble();

/// 🔹 내 위치를 폴리라인의 가장 가까운 점으로 스냅 + 거리(m) 계산
_SnapResult _snapToPolyline(double myLat, double myLng, List<dynamic> polyline) {
  if (polyline.isEmpty) {
    return _SnapResult(myLat, myLng, double.infinity);
  }

  double bestLat = myLat;
  double bestLng = myLng;
  double minDist = double.infinity;

  for (final p in polyline) {
    final double pLat = _getPointLat(p);
    final double pLng = _getPointLng(p);

    final d = Geolocator.distanceBetween(myLat, myLng, pLat, pLng);

    if (d < minDist) {
      minDist = d;
      bestLat = pLat;
      bestLng = pLng;
    }
  }

  return _SnapResult(bestLat, bestLng, minDist);
}

/// 🔹 홈 화면
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final WebViewController _controller;

  int _selectedKm = 3;
  bool _mapLoaded = false;
  bool _hasRecommendedRoute = false;
  bool _isLoadingRoute = false;

  // ============================
  // 🧊 지도 follow-throttle 변수들
  // ============================
  DateTime? _lastFollowUpdate;
  double? _lastFollowLat;
  double? _lastFollowLng;

  Map<String, dynamic>? _lastCourseData;
  int? _lastCourseKm;

  String? _currentAddress;

  CourseRoute? _courseRoute;

  bool _didInitLocation = false;

  StreamSubscription<Position>? _positionSub;
  Position? _lastPositionForAddress;

  double? _heading;
  double? _lastHeading; // (지금은 안 씀)
  DateTime? _lastHeadingUpdateTime; // (지금은 안 씀)
  StreamSubscription<CompassEvent>? _compassSub;

  double? _lastLat;
  double? _lastLng;

  bool _isOnRoute = true;
  bool _didCenterOnFirstLocation = false;

  // ⭐ 네비게이션 모드 (경로 안내 중인지)
  bool _isNavigating = false;

  // ⭐ 러닝 기록 ID
  int? _recordId;

  // ⭐ 러닝 시작 시간
  DateTime? _runStartTime;

  // ⭐ 일시정지 여부
  bool _isPaused = false;

  // ⭐ 폴리라인 이탈 기준(m)
  static const double _offRouteThresholdMeter = 30.0;

  // ⭐ 추가: 러닝 타이머
  Timer? _runTimer;
  int _elapsedSec = 0;

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (u) => debugPrint('페이지 시작: $u'),
            onPageFinished: (u) async {
              debugPrint('페이지 로드 완료: $u');
              if (!mounted) return;
              setState(() => _mapLoaded = true);

              await _initLocation();
              _startPositionStream();
              _startCompass();
            },
            onWebResourceError: (e) => debugPrint(
              '🚨 WebView 에러: ${e.errorCode} | ${e.description}',
            ),
          ),
        )
        ..loadRequest(
          Uri.parse('https://hanjiiyun.github.io/kakao_map.html?v=8'),
        );
    } else {
      _initLocation();
      _startPositionStream();
      _startCompass();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _runTimer?.cancel(); // ⭐ 추가: 타이머 정리
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ⭐ 추가: 타이머 포맷 (MM:SS 또는 HH:MM:SS)
  String _formatElapsedTime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  /// ✅ 로그인 확인
  Future<Map<String, dynamic>?> _requireLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getInt('userId');

    if (token == null || userId == null) {
      _toast('로그인을 먼저 해주세요.');
      return null;
    }
    return {'token': token, 'userId': userId};
  }

  /// 📍 현재 기기 위치
  Future<Position?> _getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _toast('위치 서비스가 꺼져 있어요. 설정에서 켜주세요.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _toast('위치 권한이 필요합니다.');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _toast('설정에서 위치 권한을 허용해 주세요.');
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// ⭐ 카카오맵 네비 모드 on/off
  Future<void> _setNavigationModeOnMap(bool enabled) async {
    if (kIsWeb || !_mapLoaded) return;
    try {
      final js = '''
      if (window.setNavigationMode) {
        window.setNavigationMode(${enabled ? 'true' : 'false'});
      }
      ''';
      await _controller.runJavaScript(js);
    } catch (e) {
      debugPrint('❌ setNavigationMode JS 오류: $e');
    }
  }

  /// ⭐ 사용자 위치 + 러너 아이콘 + 진행상황
  /// 👉 아이콘은 다시 **GPS 좌표 기준** (예전처럼), 선 색깔/이탈 체크만 스냅 좌표 사용
  Future<void> _updateUserOnMap(double lat, double lng) async {
    // 1️⃣ 기본값: 코스 위에 있다고 가정
    bool onRoute = true;

    // 2️⃣ 폴리라인 스냅은 "선/이탈 체크 전용"
    double? snapLat;
    double? snapLng;

    final polyline = _courseRoute?.polyline ?? [];
    final hasPolyline = polyline.isNotEmpty;

    if (hasPolyline) {
      final snap = _snapToPolyline(lat, lng, polyline);
      final dist = snap.distanceMeter;

      onRoute = dist <= _offRouteThresholdMeter;
      snapLat = snap.lat;
      snapLng = snap.lng;

      debugPrint('📏 dist=${dist.toStringAsFixed(1)}m | onRoute=$onRoute');
    }

    // 3️⃣ WebView 에 아이콘/지도 업데이트
    if (!kIsWeb && _mapLoaded) {
      try {
        final heading = (_heading ?? 0).toDouble();
        final onRouteJs = onRoute ? 'true' : 'false';

        // ✅ 아이콘/지도는 "실제 GPS" 기준!
        final double displayLat = lat;
        final double displayLng = lng;

        // 🟦 러너 아이콘 위치/각도
        await _controller.runJavaScript('''
          if (window.updateRunnerOnRoute) {
            window.updateRunnerOnRoute($displayLat, $displayLng, $heading, $onRouteJs);
          }
        ''');

        // ⚪️⚫️ 회색/초록 선 분리는 "폴리라인 스냅된 좌표"로만 갱신
        if (hasPolyline && snapLat != null && snapLng != null) {
          await _controller.runJavaScript('''
            if (window.updateRouteProgress) {
              window.updateRouteProgress($snapLat, $snapLng);
            }
          ''');
        }

        // =============================
        // 🧊 지도 흔들림 줄이는 follow 로직
        // =============================
        bool shouldFollow = false;
        final now = DateTime.now();

        if (!_didCenterOnFirstLocation) {
          // 처음 한 번은 무조건 내 위치 기준으로 센터
          shouldFollow = true;
        } else if (_isNavigating) {
          // 네비 모드일 때만, 일정 거리/시간 이상일 때 따라감
          final lastLat = _lastFollowLat;
          final lastLng = _lastFollowLng;
          final lastTime = _lastFollowUpdate;

          double movedMeter = 0;
          if (lastLat != null && lastLng != null) {
            movedMeter = Geolocator.distanceBetween(
              lastLat,
              lastLng,
              displayLat,
              displayLng,
            );
          }

          final bool movedEnough = movedMeter > 8; // 8m 이상 움직였을 때만
          final bool timeEnough = lastTime == null ||
              now.difference(lastTime).inMilliseconds > 700; // 0.7초 이상

          shouldFollow = movedEnough && timeEnough;
        }

        if (shouldFollow) {
          await _controller.runJavaScript('''
            if (window.followUser) {
              window.followUser($displayLat, $displayLng);
            }
          ''');

          _didCenterOnFirstLocation = true;
          _lastFollowUpdate = now;
          _lastFollowLat = displayLat;
          _lastFollowLng = displayLng;
        }
      } catch (e) {
        debugPrint('❌ updateUserOnMap error: $e');
      }
    }

    // 4️⃣ 코스 이탈 토스트
    if (hasPolyline && mounted && onRoute != _isOnRoute && _isNavigating) {
      final wasOnRoute = _isOnRoute;
      setState(() => _isOnRoute = onRoute);

      if (!onRoute && wasOnRoute) {
        _toast('코스를 이탈했어요!');
      } else if (onRoute && !wasOnRoute) {
        _toast('코스로 복귀했습니다!');
      }
    }
  }

  /// ⭐ 첫 진입 위치 + 주소 설정
  Future<void> _initLocation() async {
    if (_didInitLocation) return;
    _didInitLocation = true;

    final position = await _getCurrentPosition();
    if (position == null) return;

    final lat = position.latitude;
    final lng = position.longitude;

    _lastLat = lat;
    _lastLng = lng;

    await _updateAddressFromLatLng(lat, lng);
    _lastPositionForAddress = position;

    await _updateUserOnMap(lat, lng);
  }

  /// ⭐ 위치 스트림
  void _startPositionStream() async {
    final position = await _getCurrentPosition();
    if (position == null) return;

    await _positionSub?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0, // 🔥 최대한 자주 업데이트
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((pos) async {
      final newLat = pos.latitude;
      final newLng = pos.longitude;

      _lastLat = newLat;
      _lastLng = newLng;

      await _updateUserOnMap(_lastLat!, _lastLng!);

      // 주소 업데이트는 80m마다
      if (_lastPositionForAddress == null ||
          Geolocator.distanceBetween(
                  _lastPositionForAddress!.latitude,
                  _lastPositionForAddress!.longitude,
                  newLat,
                  newLng) > 80) {
        _lastPositionForAddress = pos;
        await _updateAddressFromLatLng(newLat, newLng);
      }
    });
  }

  void _startCompass() {
    _compassSub?.cancel();

    _compassSub = FlutterCompass.events?.listen((event) {
      final raw = event.heading;
      if (raw == null) return;

      double newHeading = raw;
      if (newHeading < 0) newHeading += 360;
      if (newHeading >= 360) newHeading -= 360;

      _heading = newHeading;

      if (_lastLat != null && _lastLng != null) {
        _updateUserOnMap(_lastLat!, _lastLng!);
      }
    });
  }

  /// 📍 위도/경도 → 시/구/동
  Future<void> _updateAddressFromLatLng(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        final si = p.administrativeArea ?? '';
        final gu = p.subLocality ?? p.locality ?? p.subAdministrativeArea ?? '';
        final dong = p.thoroughfare ?? p.subThoroughfare ?? '';

        final addr = [si, gu, dong].where((s) => s.trim().isNotEmpty).join(' ');

        setState(() {
          _currentAddress = addr.trim();
        });

        debugPrint('📍 현재 주소(시/구/동): $_currentAddress');
      }
    } catch (e) {
      debugPrint('❌ 주소 변환 실패: $e');
    }
  }

  /// ✅ 거리별 코스 추천
  Future<void> _fetchRecommendedRoute(int km) async {
    setState(() {
      _isLoadingRoute = true;
      _isNavigating = false;
      _recordId = null;
      _isPaused = false;
      _runStartTime = null;

      // 💡 새 코스 요청이니까 이전 코스 상태는 여기서 리셋
      _hasRecommendedRoute = false;
      _lastCourseData = null;
      _courseRoute = null;
      _isOnRoute = true;

      // 🧊 지도 센터/따라가기 관련 초기화
      _didCenterOnFirstLocation = false;
      _lastFollowLat = null;
      _lastFollowLng = null;
      _lastFollowUpdate = null;

      _elapsedSec = 0;      // ⭐ 타이머도 초기화
      _runTimer?.cancel();
    });

    await _setNavigationModeOnMap(false);

    if (kIsWeb) {
      debugPrint('⚠ Web 환경에서는 경로 표시 미지원');
      setState(() {
        _isLoadingRoute = false;
      });
      return;
    }

    if (!_mapLoaded) {
      _toast('지도가 아직 로딩 중입니다. 잠시만 기다려 주세요.');
      setState(() {
        _isLoadingRoute = false;
      });
      return;
    }

    final position = await _getCurrentPosition();
    if (position == null) {
      setState(() {
        _isLoadingRoute = false;
      });
      return;
    }

    final lat = position.latitude;
    final lng = position.longitude;

    await _updateAddressFromLatLng(lat, lng);
    _lastPositionForAddress = position;

    await _updateUserOnMap(lat, lng);

    final uri = Uri.parse('$baseUrl/api/courses/recommend').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'km': km.toString(),
        'ts': DateTime.now().millisecondsSinceEpoch.toString(), // ✅ 캐시 깨기용
      },
    );

    try {
      debugPrint('📡 GET $uri');
      final response = await http.get(uri);
      debugPrint('📡 route status: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

        CourseRoute? parsedRoute;
        try {
          parsedRoute = CourseRoute.fromJson(data);
          debugPrint(
              '✅ CourseRoute 파싱 성공: polyline=${parsedRoute.polyline.length}, turns=${parsedRoute.turns.length}');
        } catch (e) {
          debugPrint('❌ CourseRoute 파싱 실패: $e');
        }

        setState(() {
          _hasRecommendedRoute = true;
          _lastCourseData = data;
          _lastCourseKm = km;
          _courseRoute = parsedRoute;
          _isOnRoute = true;
          _isNavigating = false;
          _recordId = null;
          _isPaused = false;
          _runStartTime = null;
        });

        try {
          await _controller.runJavaScript(
            '''
            if (typeof showRecommendedRoute === "function") {
              showRecommendedRoute(${jsonEncode(data)});
            } else {
              console.log("showRecommendedRoute not defined");
            }
            ''',
          );
        } catch (e) {
          debugPrint('❌ JS 실행 오류: $e');
          _toast('지도를 그리는 중 오류가 발생했습니다.');
        }

        await _updateUserOnMap(lat, lng);
      } else {
        _toast('경로를 불러오지 못했습니다. (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('❌ _fetchRecommendedRoute error: $e');
      if (!mounted) return;
      _toast('경로 조회 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }

  void _reFetchRoute() {
    // 🚫 이미 경로를 불러오는 중이면 무시
    if (_isLoadingRoute) return;
    _showKmPopup();
  }

  /// 🔹 러닝 시작 (코스 저장 + run-records/start)
  Future<void> _onStartRunningPressed() async {
    if (_lastCourseData == null) {
      _toast('먼저 코스를 추천받아 주세요.');
      return;
    }

    final loginInfo = await _requireLogin();
    if (loginInfo == null) return;

    final token = loginInfo['token'] as String;
    final userId = loginInfo['userId'] as int;

    _toast('코스를 저장하고 러닝을 시작합니다...');

    // 1️⃣ 코스 저장 → courseId 받기
    final courseResult = await startCourseApi(
      token: token,
      userId: userId,
      courseData: _lastCourseData!,
      km: _lastCourseKm ?? _selectedKm,
    );

    if (courseResult == null) {
      _toast('코스 저장 중 오류가 발생했습니다.');
      return;
    }

    final courseStatus = courseResult['statusCode'] as int? ?? 0;
    final courseBody = (courseResult['body'] as Map<String, dynamic>?) ?? {};

    final int? courseId = courseBody['courseId'] as int?;
    debugPrint('📡 /api/courses/start ⇒ status=$courseStatus, body=$courseBody');

    if (courseId == null) {
      _toast('코스 ID를 받지 못했습니다. 서버 응답을 확인해 주세요.');
      return;
    }

    if (!(courseStatus == 200 || courseStatus == 201)) {
      _toast('코스 저장 실패 ($courseStatus)');
      return;
    }

    // 2️⃣ run-records/start 호출 → recordId 받기
    final runResult = await startRunRecordApi(
      token: token,
      userId: userId,
      courseId: courseId,
    );

    if (runResult == null) {
      _toast('러닝 기록 시작 중 오류가 발생했습니다. (null 응답)');
      return;
    }

    final runStatus = runResult['statusCode'] as int? ?? 0;
    final int? recordId = runResult['recordId'] as int?;
    final rawBody = runResult['rawBody'];

    debugPrint(
        '🏃‍♀️ /api/run-records/start ⇒ status=$runStatus, recordId=$recordId, body=$rawBody');

    _toast('run-start: $runStatus / $rawBody');

    if (!(runStatus == 200 || runStatus == 201) || recordId == null) {
      return;
    }

    final DateTime startedAt = DateTime.now();

    setState(() {
      _isNavigating = true;
      _isPaused = false;
      _recordId = recordId;
      _runStartTime = startedAt;
      _elapsedSec = 0; // ⭐ 타이머 초기화
    });

    // ⭐ 타이머 시작
    _runTimer?.cancel();
    _runTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isPaused && mounted && _recordId != null) {
        setState(() {
          _elapsedSec++;
        });
      }
    });

    await _setNavigationModeOnMap(true);

    final double distanceKm = (_lastCourseKm ?? _selectedKm).toDouble();
    final String courseName =
        'AI 추천 코스 ${distanceKm.toStringAsFixed(1)}km';

    await run_storage.addRunRecord(
      run_storage.RunRecord(
        userId: userId,
        date: startedAt,
        name: courseName,
        distanceKm: distanceKm,
      ),
    );
    debugPrint(
        '📅 Local RunRecord saved: $courseName / ${distanceKm}km / $startedAt');
  }

  Future<void> _onPausePressed() async {
    if (_recordId == null) return;

    final loginInfo = await _requireLogin();
    if (loginInfo == null) return;
    final token = loginInfo['token'] as String;

    final result = await pauseRunRecordApi(
      token: token,
      recordId: _recordId!,
    );

    if (result == null) {
      _toast('일시정지 중 오류가 발생했습니다.');
      return;
    }

    final status = result['statusCode'] as int? ?? 0;
    if (status == 200 || status == 201) {
      _toast('러닝이 일시정지되었습니다.');
      setState(() {
        _isPaused = true;
      });
    } else {
      _toast('일시정지 실패 ($status)');
    }
  }

  Future<void> _onResumePressed() async {
    if (_recordId == null) return;

    final loginInfo = await _requireLogin();
    if (loginInfo == null) return;
    final token = loginInfo['token'] as String;

    final result = await resumeRunRecordApi(
      token: token,
      recordId: _recordId!,
    );

    if (result == null) {
      _toast('재시작 중 오류가 발생했습니다.');
      return;
    }

    final status = result['statusCode'] as int? ?? 0;
    if (status == 200 || status == 201) {
      _toast('러닝을 재시작합니다.');
      setState(() {
        _isPaused = false;
      });
    } else {
      _toast('재시작 실패 ($status)');
    }
  }

  Future<void> _onFinishPressed() async {
    // ⭐ 러닝 종료 시 타이머는 무조건 멈추기
    _runTimer?.cancel();

    // recordId 없으면 그냥 상태만 초기화 + 맨 처음 화면으로
    if (_recordId == null) {
      setState(() {
        _isNavigating = false;
        _isPaused = false;
        _runStartTime = null;
        _elapsedSec = 0;

        // 🔙 맨 처음 상태로 복귀
        _recordId = null;
        _hasRecommendedRoute = false;
        _lastCourseData = null;
        _lastCourseKm = null;
        _courseRoute = null;
        _isOnRoute = true;
      });
      await _setNavigationModeOnMap(false);
      return;
    }

    final loginInfo = await _requireLogin();
    if (loginInfo == null) return;
    final token = loginInfo['token'] as String;

    double distanceM = 0;
    final summary = _lastCourseData?['summary'] as Map<String, dynamic>?;

    if (summary != null && summary['length_m'] != null) {
      distanceM = (summary['length_m'] as num).toDouble();
    } else {
      distanceM = (_lastCourseKm ?? _selectedKm).toDouble() * 1000.0;
    }

    // ⭐ durationSec: 실제 화면에 올라간 러닝 시간 사용
    int durationSec = _elapsedSec;

    final result = await finishRunRecordApi(
      token: token,
      recordId: _recordId!,
      distanceM: distanceM,
      durationSec: durationSec,
      avgHeartRate: null,
      maxHeartRate: null,
      calories: null,
    );

    if (result == null) {
      _toast('러닝 종료 중 오류가 발생했습니다.');
      return;
    }

    final status = result['statusCode'] as int? ?? 0;
    if (status == 200 || status == 201) {
      _toast('러닝을 종료했습니다.');
    } else {
      _toast('러닝 종료 실패 ($status)');
    }

    if (!mounted) return;

    setState(() {
      _isNavigating = false;
      _isPaused = false;
      _recordId = null;
      _runStartTime = null;
      _elapsedSec = 0;

      // 🔙 맨 처음 상태로 복귀
      _hasRecommendedRoute = false;
      _lastCourseData = null;
      _lastCourseKm = null;
      _courseRoute = null;
      _isOnRoute = true;
    });

    await _setNavigationModeOnMap(false);
  }

  /// 🔹 거리 선택 팝업
  void _showKmPopup() async {
    // 🚫 이미 경로를 불러오는 중이면 팝업 안 띄움
    if (_isLoadingRoute) return;

    final loginInfo = await _requireLogin();
    if (loginInfo == null) return;

    showGeneralDialog(
      context: context,
      barrierLabel: '거리 선택',
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) {
        int tempKm = _selectedKm;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: StatefulBuilder(
                  builder: (context, setStateDialog) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "거리 선택",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.green,
                            inactiveTrackColor: Colors.greenAccent,
                            thumbColor: Colors.green,
                            overlayColor:
                                Colors.greenAccent.withOpacity(0.2),
                            trackHeight: 4,
                            valueIndicatorColor: Colors.green,
                          ),
                          child: Slider(
                            value: tempKm.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            label: "${tempKm}km",
                            onChanged: (value) =>
                                setStateDialog(() => tempKm = value.toInt()),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(5, (i) {
                            final v = i + 1;
                            final on = v == tempKm;
                            return Column(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: on ? Colors.green : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$v km",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: on
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: on ? Colors.green : Colors.grey,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 42,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();

                              if (!mounted) return;
                              setState(() {
                                _selectedKm = tempKm;
                              });

                              debugPrint("✅ 선택된 거리: $_selectedKm km");
                              // 👉 여기서 바로 새 코스 요청 (초기/재추천 둘 다 동일 흐름)
                              _fetchRecommendedRoute(_selectedKm);
                            },
                            child: const Text(
                              "전송",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(anim),
            child: child,
          ),
        );
      },
    );
  }

  /// 🔹 턴 타입별 아이콘
  IconData _turnIcon(String type) {
    switch (type) {
      case 'right':
        return Icons.turn_right;
      case 'left':
        return Icons.turn_left;
      case 'straight':
        return Icons.straight;
      default:
        return Icons.directions_walk;
    }
  }

  /// 🔹 턴 안내 패널 (네비게이션 중일 때만)
  Widget _buildTurnPanel() {
    if (_courseRoute == null || _courseRoute!.turns.isEmpty) {
      return const SizedBox.shrink();
    }

    final turns = _courseRoute!.turns;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '턴 안내',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            child: ListView.separated(
              itemCount: turns.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final t = turns[index];
                final dist = t.atDistM.round();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _turnIcon(t.type),
                    color: Colors.green,
                  ),
                  title: Text(
                    t.instruction,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${dist}m 앞',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 메인 버튼 텍스트 + 동작 (러닝 중/일시정지일 때만 사용)
    String buttonText;
    VoidCallback? onMainButtonPressed;

    if (_isLoadingRoute) {
      buttonText = "추천 경로 설정중...";
      onMainButtonPressed = null;
    } else if (!_hasRecommendedRoute) {
      buttonText = "경로 추천 시작";
      onMainButtonPressed = () {
        _showKmPopup();
      };
    } else if (_recordId == null) {
      buttonText = "출발!";
      onMainButtonPressed = () {
        _onStartRunningPressed();
      };
    } else if (!_isPaused) {
      buttonText = "일시정지";
      onMainButtonPressed = () {
        _onPausePressed();
      };
    } else {
      buttonText = "재시작";
      onMainButtonPressed = () {
        _onResumePressed();
      };
    }

    return Scaffold(
      appBar: const R2UAppBar(),
      body: Column(
        children: [
          Expanded(
            child: kIsWeb
                ? const Center(
                    child: Text(
                      "여기에 지도가 들어갈 예정",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : Stack(
                    children: [
                      WebViewWidget(controller: _controller),
                    ],
                  ),
          ),

          if (_isNavigating &&
              _courseRoute != null &&
              _courseRoute!.turns.isNotEmpty)
            _buildTurnPanel(),

          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '현재 위치',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 18,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _currentAddress ?? '현재 위치 불러오는중.....♡',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 🔹 아직 러닝 시작 전
                if (_recordId == null) ...[
                  // ✅ 경로 불러오는 중이면: 비활성화 버튼 하나만
                  if (_isLoadingRoute)
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade400,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        onPressed: null, // 비활성화
                        child: const Text(
                          "경로 추천 중...",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else if (!_hasRecommendedRoute)
                    // 👉 코스 아직 없음: 버튼 1개 (경로 추천 시작)
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _showKmPopup,
                        child: const Text(
                          "경로 추천 시작",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else
                    // 👉 코스 추천 완료: 경로 재추천 + 출발 버튼 2개
                    Row(
                      children: [
                        // 경로 재추천
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.green),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _reFetchRoute,
                              child: const Text(
                                "경로 재추천",
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 출발 버튼
                        Expanded(
                          child: SizedBox(
                            height: 45,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 0,
                              ),
                              onPressed: _onStartRunningPressed,
                              child: const Text(
                                "출발!",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ]

                // 🔹 러닝 중 / 일시정지 상태
                else ...[
                  // ⭐ 추가: 러닝 타이머 표시
                  Row(
                    children: [
                      const Icon(
                        Icons.timer,
                        size: 18,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatElapsedTime(_elapsedSec),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 45,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            onPressed: onMainButtonPressed,
                            child: Text(
                              buttonText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 45,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.green),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              backgroundColor: Colors.white,
                            ),
                            onPressed: _onFinishPressed,
                            child: const Text(
                              "러닝 종료",
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}