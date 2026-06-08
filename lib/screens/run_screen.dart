import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../controllers/run_controllers.dart';

class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  late final WebViewController _webViewController;
  final RunController _runController = RunController();

  StreamSubscription<Position>? _positionSub;

  bool _isRunning = false;
  DateTime? _startTime;

  Position? _lastPosition;
  final List<Position> _routePositions = [];
  double _totalDistanceKm = 0.0;

  // TODO: 나중에 실제 로그인된 사용자 ID로 교체하기
  final int _dummyUserId = 1;

  @override
  void initState() {
    super.initState();

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadFlutterAsset('assets/kakao_map.html');
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // 1. 위치 권한 / 서비스 체크
  // ─────────────────────────────────────────────
  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치 서비스가 꺼져 있습니다. 켜주세요.')),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치 권한이 필요합니다.')),
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('설정에서 위치 권한을 영구적으로 허용해야 합니다.'),
        ),
      );
      return false;
    }

    return true;
  }

  // ─────────────────────────────────────────────
  // 2. 러닝 시작
  // ─────────────────────────────────────────────
  Future<void> _startRunning() async {
    final ok = await _ensureLocationPermission();
    if (!ok) return;

    // 초기 위치 1회
    final Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    _routePositions.clear();
    _routePositions.add(pos);
    _lastPosition = pos;
    _totalDistanceKm = 0.0;
    _startTime = DateTime.now();

    // 카카오맵에 초기 위치 전달 (kakao_map.html에 함수 있어야 함)
    _sendPositionToKakao(pos);

    // 위치 스트림 구독 시작
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // 5m 이상 이동 시만 콜백
      ),
    ).listen(_onPositionUpdate);

    setState(() {
      _isRunning = true;
    });
  }

  // 위치 업데이트 처리
  void _onPositionUpdate(Position pos) {
    if (_lastPosition != null) {
      final double distMeters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      _totalDistanceKm += distMeters / 1000.0;
    }

    _routePositions.add(pos);
    _lastPosition = pos;

    // 카카오맵에 새 위치 전달
    _sendPositionToKakao(pos);

    if (mounted) {
      setState(() {});
    }
  }

  // Dart → Kakao WebView 로 위치 전달
  void _sendPositionToKakao(Position pos) {
  // kakao_map.html 안의 showUserLocation(lat, lng) 호출
  _webViewController.runJavaScript(
    'showUserLocation(${pos.latitude}, ${pos.longitude});',
  );
}


  // ─────────────────────────────────────────────
  // 3. 러닝 종료 + 서버/헬스 저장
  // ─────────────────────────────────────────────
  Future<void> _stopRunningAndSave() async {
    if (!_isRunning || _startTime == null) return;

    final DateTime endTime = DateTime.now();

    await _positionSub?.cancel();
    _positionSub = null;

    final String polylineData = _encodeRouteToJson(_routePositions);

    final success = await _runController.finishRunAndSave(
      context: context,
      userId: _dummyUserId, // TODO: 실제 userId로 교체
      distanceKm: _totalDistanceKm,
      startTime: _startTime!,
      endTime: endTime,
      polylineData: polylineData,
    );

    if (success) {
      setState(() {
        _isRunning = false;
        _startTime = null;
        _lastPosition = null;
        _routePositions.clear();
        _totalDistanceKm = 0.0;
      });
    }
  }

  // 경로 좌표들을 JSON 문자열로 인코딩 (서버 전송용)
  String _encodeRouteToJson(List<Position> positions) {
    final list = positions
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();
    return jsonEncode(list);
  }

  // ─────────────────────────────────────────────
  // 4. UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('러닝 트래커 (카카오맵)'),
      ),
      body: Column(
        children: [
          // 지도 영역 (카카오맵 WebView)
          Expanded(
            flex: 3,
            child: WebViewWidget(controller: _webViewController),
          ),

          // 정보 + 버튼 영역
          Expanded(
            flex: 2,
            child: _buildInfoPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel() {
    final String durationText = _startTime == null
        ? '00:00'
        : _formatDuration(DateTime.now().difference(_startTime!));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 4,
            color: Colors.black12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _isRunning ? '러닝 중' : '대기 중',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            '시간: $durationText',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            '거리: ${_totalDistanceKm.toStringAsFixed(2)} km',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isRunning)
                ElevatedButton(
                  onPressed: _startRunning,
                  child: const Text('러닝 시작'),
                ),
              if (_isRunning)
                ElevatedButton(
                  onPressed: _stopRunningAndSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: const Text('러닝 종료 & 저장'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final int minutes = d.inMinutes;
    final int seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
