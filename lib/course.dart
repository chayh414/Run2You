// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

// =========================================================
// 1. 앱 진입점 (main 함수)
// =========================================================
void main() {
  // 앱 실행 전에 위치 권한 요청 및 초기화 코드가 필요할 수 있습니다.
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    // 상태 관리를 위해 앱 전체에 RunningState를 제공합니다.
    ChangeNotifierProvider(
      create: (context) => RunningState(),
      child: const RunningTrackerApp(),
    ),
  );
}

class RunningTrackerApp extends StatelessWidget {
  const RunningTrackerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Running Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const RunningScreen(),
    );
  }
}

// =========================================================
// 2. 상태 관리 클래스 (RunningState)
// =========================================================
class RunningState extends ChangeNotifier {
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  int _secondsElapsed = 0;
  int get secondsElapsed => _secondsElapsed;
  Timer? _timer;

  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;
  double _totalDistance = 0.0; 
  double get totalDistance => _totalDistance;
  final List<Position> _pathCoordinates = []; 
  List<Position> get pathCoordinates => _pathCoordinates;

  StreamSubscription<Position>? _positionStreamSubscription;
  
  void _reset() {
    _isRunning = false;
    _secondsElapsed = 0;
    _totalDistance = 0.0;
    _pathCoordinates.clear();
    _currentPosition = null;
    notifyListeners();
  }

  // 위치 추적 시작
  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // 위치 서비스가 비활성화된 경우 사용자에게 알림 필요
      return Future.error('Location services are disabled.');
    }
    
    // 위치 권한 확인 (앱 시작 전에 처리하는 것이 좋음)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 10, // 10m 이동 시 업데이트
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings)
        .listen((Position position) {
      _updateRunningData(position);
    });
  }

  // 실시간 데이터 업데이트 로직
  void _updateRunningData(Position newPosition) {
    if (!_isRunning) return;

    if (_currentPosition != null) {
      // 거리 계산 및 누적 (미터 -> km)
      double distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );
      _totalDistance += distanceInMeters / 1000.0;
    }

    _currentPosition = newPosition;
    _pathCoordinates.add(newPosition);

    notifyListeners();
  }

  void startRun() {
    if (_isRunning) return;
    _reset();
    _isRunning = true;
    _startTimer();
    _startLocationTracking();
    notifyListeners();
  }

  void stopRun() {
    _timer?.cancel();
    _positionStreamSubscription?.cancel();
    _reset();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsElapsed++;
      notifyListeners();
    });
  }
}

// =========================================================
// 3. UI 화면 (RunningScreen)
// =========================================================
class RunningScreen extends StatelessWidget {
  const RunningScreen({super.key});

  // 카카오맵 표시 영역 (실제 연동 코드를 대신하는 플레이스홀더)
  Widget _buildKakaoMapView(List<Position> path, Position? currentPos) {
    // 🚨 여기에 실제 카카오맵 연동 코드가 들어갑니다. (WebView 또는 SDK 연동)
    // - path 좌표 리스트를 지도에 폴리라인으로 그립니다.
    // - currentPos를 현재 사용자 위치 마커로 표시합니다.

    return Container(
      color: Colors.blueGrey[50],
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🗺️ 카카오맵 표시 영역', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('서버 연동을 통해 지도, 현재 위치, 경로가 표시됩니다.'),
          Text('현재 경로 좌표 수: ${path.length}개'),
          if (currentPos != null)
            Text('현재 위치: ${currentPos.latitude.toStringAsFixed(4)}, ${currentPos.longitude.toStringAsFixed(4)}'),
        ],
      ),
    );
  }
  
  // 초를 시:분:초 형식으로 변환
  String _formatTime(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  // 러닝 정보 패널 위젯
  Widget _buildInfoPanel(int seconds, double distance) {
    String formattedTime = _formatTime(seconds);
    String formattedDistance = distance.toStringAsFixed(2);
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoCard('시간', formattedTime, Icons.timer),
          _infoCard('거리', '$formattedDistance km', Icons.directions_run),
        ],
      ),
    );
  }
  
  // 정보 카드 위젯
  Widget _infoCard(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 30, color: Colors.blueAccent),
        Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // RunningState를 구독하여 상태가 변경될 때마다 화면이 업데이트됩니다.
    final runningState = Provider.of<RunningState>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('러닝 트래커'), centerTitle: true),
      body: Column(
        children: <Widget>[
          // 1. 지도 영역
          Expanded(
            child: _buildKakaoMapView(
              runningState.pathCoordinates, 
              runningState.currentPosition,
            ),
          ),
          
          // 2. 러닝 정보 패널
          _buildInfoPanel(
            runningState.secondsElapsed, 
            runningState.totalDistance,
          ),
          
          // 3. 컨트롤 버튼
          Padding(
            padding: const EdgeInsets.only(bottom: 30.0),
            child: runningState.isRunning
                ? FloatingActionButton.extended(
                    onPressed: runningState.stopRun,
                    label: const Text('러닝 종료', style: TextStyle(fontSize: 18)),
                    icon: const Icon(Icons.stop, size: 24),
                    backgroundColor: Colors.red,
                  )
                : FloatingActionButton.extended(
                    onPressed: runningState.startRun,
                    label: const Text('러닝 시작', style: TextStyle(fontSize: 18)),
                    icon: const Icon(Icons.play_arrow, size: 24),
                    backgroundColor: Colors.green,
                  ),
          ),
        ],
      ),
    );
  }
}