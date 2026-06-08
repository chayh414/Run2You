// lib/screens/calendar_screen.dart

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_screen.dart';
import '../utils/run_storage.dart' as run_storage;
import '../services/aws_services.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  bool _isLoading = true;
  int? _userId;

  /// 날짜별 러닝 기록 (키는 yyyy-MM-dd 로 normalize 한 날짜)
  final Map<DateTime, List<run_storage.RunRecord>> _dailyMap = {};

  /// 🔹 서버 API 연동용 상태 변수 (월 통계 / 일자별 서버 기록)
  RunSummary? _monthlySummary;              // 월 통계 요약 (아직 UI엔 안 씀)
  List<RunRecord> _monthlyRecords = [];     // 해당 월 서버 기록 리스트
  List<RunRecord> _dailyApiRecords = [];    // 선택한 날짜 서버 기록 리스트

  @override
  void initState() {
    super.initState();
    // 기존: 로컬 기록 로드 → 끝난 뒤 서버 월 데이터도 같이 가져오도록
    _loadRecords();
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (!mounted) return;

    if (userId == null) {
      // 로그인 안 된 상태
      setState(() {
        _userId = null;
        _dailyMap.clear();
        _isLoading = false;
      });
      return;
    }

    final records = await run_storage.getRecordsForUser(userId);

    final Map<DateTime, List<run_storage.RunRecord>> grouped = {};
    for (final r in records) {
      final k = _dayKey(r.date);
      grouped.putIfAbsent(k, () => []).add(r);
    }

    setState(() {
      _userId = userId;
      _dailyMap
        ..clear()
        ..addAll(grouped);
      _isLoading = false;
    });

    // ✅ 로컬 기록 로드 후, 서버에서 이번 달 월 통계/기록도 가져오기
    print('[CAL] _loadRecords done. userId=$_userId, days=${_dailyMap.length}');
    _loadMonthlyData(_focusedDay);
  }

  /// 🔹 서버에서 월 데이터(요약 + 기록 리스트) 가져오기
  Future<void> _loadMonthlyData(DateTime month) async {
    if (_userId == null) {
      print('[CAL] _loadMonthlyData skip: userId is null');
      return;
    }

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);

    print('[CAL] _loadMonthlyData request: userId=$_userId, $start ~ $end');

    try {
      final response = await fetchRunRecords(
        userId: _userId!,
        start: start,
        end: end,
      );

      if (!mounted) return;

      setState(() {
        _monthlySummary = response.summary;
        _monthlyRecords = response.records;
      });

      print(
        '[CAL] _loadMonthlyData ok: runs=${response.summary.runCount}, '
        'distance_m=${response.summary.totalDistanceM}',
      );
    } catch (e) {
      print('[CAL] _loadMonthlyData error: $e');
    }
  }

  /// 🔹 서버에서 특정 날짜 데이터 가져오기
  Future<void> _loadDailyData(DateTime day) async {
    if (_userId == null) {
      print('[CAL] _loadDailyData skip: userId is null');
      return;
    }

    final start = DateTime(day.year, day.month, day.day);
    final end = start;

    print('[CAL] _loadDailyData request: userId=$_userId, day=$start');

    try {
      final response = await fetchRunRecords(
        userId: _userId!,
        start: start,
        end: end,
      );

      if (!mounted) return;

      setState(() {
        _dailyApiRecords = response.records;
      });

      print('[CAL] _loadDailyData ok: records=${response.records.length}');
    } catch (e) {
      print('[CAL] _loadDailyData error: $e');
    }
  }

  List<run_storage.RunRecord> _getDailyRecord(DateTime day) {
    return _dailyMap[_dayKey(day)] ?? const <run_storage.RunRecord>[];
  }

  List<run_storage.RunRecord> _getMonthlyRecords(DateTime day) {
    final y = day.year;
    final m = day.month;
    final List<run_storage.RunRecord> list = [];
    _dailyMap.forEach((d, rs) {
      if (d.year == y && d.month == m) {
        list.addAll(rs);
      }
    });
    return list;
  }

  // ⭐ 추가: duration, 시작시간, 메타칩 관련 헬퍼들 -------------------

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  String _formatStartTime(DateTime dt) {
    final isPm = dt.hour >= 12;
    final hour = dt.hour == 0
        ? 12
        : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    return '${isPm ? "오후" : "오전"} $hour:$min';
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  /// ⭐ 추가: 서버에서 가져온 _dailyApiRecords 기준 일별 상세 UI
  Widget _buildDailyDetailFromApi() {
    if (_dailyApiRecords.isEmpty) {
      return const Center(
        child: Text(
          "이 날에는 저장된 러닝 기록이 없어요.",
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView.separated(
        itemCount: _dailyApiRecords.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, i) {
          final r = _dailyApiRecords[i];

          final double distanceKm = r.distanceM / 1000.0;
          final int duration = r.durationSec;
          final DateTime startedAt = r.startedAt;

          final List<Widget> meta = [];

          if (r.avgHeartRate > 0) {
            meta.add(_metaChip('평균 심박수 ${r.avgHeartRate} bpm'));
          }
          if (r.maxHeartRate > 0) {
            meta.add(_metaChip('최대 심박수 ${r.maxHeartRate} bpm'));
          }
          if (r.calories > 0) {
            meta.add(_metaChip('칼로리 ${r.calories} kcal'));
          }
          if (r.paceStr.isNotEmpty) {
            meta.add(_metaChip('페이스 ${r.paceStr}'));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1줄: 거리 + 시간 + 시작시간
              Row(
                children: [
                  Text(
                    '${distanceKm.toStringAsFixed(2)} km',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatStartTime(startedAt),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              // 2줄: 심박/칼로리/페이스 칩들 (값 있을 때만)
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: meta,
                ),
              ],

              const Divider(height: 20),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('[CAL] build called, userId=$_userId');

    final bool hasSelected = _selectedDay != null;
    final List<run_storage.RunRecord> dailyRecords =
        hasSelected ? _getDailyRecord(_selectedDay!) : const <run_storage.RunRecord>[];
    final List<run_storage.RunRecord> monthlyRecords =
        _getMonthlyRecords(_focusedDay);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ---------- 상단 월 이동 + 설정 ----------
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _focusedDay = DateTime(
                          _focusedDay.year,
                          _focusedDay.month - 1,
                          1,
                        );
                        _selectedDay = null;
                      });
                      // 🔹 월 바뀔 때 서버 월 데이터 다시 가져오기
                      if (_userId != null) {
                        _loadMonthlyData(_focusedDay);
                      }
                    },
                    child: const Icon(Icons.chevron_left, size: 30),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        "${_focusedDay.year}년 ${_focusedDay.month}월",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _focusedDay = DateTime(
                          _focusedDay.year,
                          _focusedDay.month + 1,
                          1,
                        );
                        _selectedDay = null;
                      });
                      // 🔹 월 바뀔 때 서버 월 데이터 다시 가져오기
                      if (_userId != null) {
                        _loadMonthlyData(_focusedDay);
                      }
                    },
                    child: const Icon(Icons.chevron_right, size: 30),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsPage(),
                        ),
                      );
                    },
                    child: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),

            // ---------- 달력 ----------
            Flexible(
              fit: FlexFit.loose,
              child: SizedBox(
                height: 260,
                child: TableCalendar<run_storage.RunRecord>(
                  locale: 'ko_KR',
                  firstDay: DateTime(2020),
                  lastDay: DateTime(2035),
                  focusedDay: _focusedDay,
                  calendarFormat: CalendarFormat.month,
                  headerVisible: false,

                  // 줄 높이/요일 줄 높이 줄이기
                  rowHeight: 34,
                  daysOfWeekHeight: 18,

                  selectedDayPredicate: (day) =>
                      _selectedDay != null &&
                      _dayKey(day) == _dayKey(_selectedDay!),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    // 🔹 날짜 선택 시 서버에서 해당 날짜 기록도 가져오기
                    if (_userId != null) {
                      _loadDailyData(selectedDay);
                    }
                  },
                  onPageChanged: (day) {
                    setState(() {
                      _focusedDay = day;
                      _selectedDay = null;
                    });
                    // 🔹 스와이프로 달 넘길 때 월 데이터 다시 가져오기
                    if (_userId != null) {
                      _loadMonthlyData(_focusedDay);
                    }
                  },

                  // 날짜별 이벤트(러닝 기록)
                  eventLoader: _getDailyRecord,

                  // 🔹 동그라미 1개 + 개수 많을수록 진하게 (선택된 날은 숨김)
                  calendarBuilders:
                      CalendarBuilders<run_storage.RunRecord>(
                    markerBuilder: (context, day, events) {
                      if (events.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      // 선택된 날짜에서는 동그라미 숨기기
                      if (_selectedDay != null &&
                          _dayKey(day) == _dayKey(_selectedDay!)) {
                        return const SizedBox.shrink();
                      }

                      final count = events.length;
                      final int clamped = count.clamp(1, 4);

                      // 최소 0.25 ~ 최대 1.0
                      final double opacity =
                          0.25 + (0.75 * (clamped - 1) / 3);

                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(opacity),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    },
                  ),

                  daysOfWeekStyle: const DaysOfWeekStyle(
                    weekdayStyle: TextStyle(fontSize: 11),
                    weekendStyle:
                        TextStyle(fontSize: 11, color: Colors.red),
                  ),
                  calendarStyle: const CalendarStyle(
                    defaultTextStyle: TextStyle(fontSize: 12),
                    weekendTextStyle:
                        TextStyle(fontSize: 12, color: Colors.red),
                    todayDecoration: BoxDecoration(
                      color: Color(0xFFB2DFDB),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    cellPadding: EdgeInsets.zero,
                    tablePadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ---------- 아래 영역 ----------
            Flexible(
              fit: FlexFit.loose,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : hasSelected
                      ? (
                          // ⭐ 서버 데이터 우선, 없으면 로컬 fallback
                          _dailyApiRecords.isNotEmpty
                              ? _buildDailyDetailFromApi()
                              : (dailyRecords.isNotEmpty
                                  ? _buildDailyDetail(dailyRecords)
                                  : const Center(
                                      child: Text(
                                        "이 날에는 저장된 러닝 기록이 없어요.",
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ))
                        )
                      : _buildMonthlySummary(monthlyRecords),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 월 통계 ----------------
  Widget _buildMonthlySummary(List<run_storage.RunRecord> list) {
    if (_userId == null) {
      return const Center(
        child: Text(
          "로그인 후 러닝 기록을 볼 수 있어요.",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    if (list.isEmpty) {
      return const Center(
        child: Text(
          "이번 달 러닝 기록이 없어요.",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    // ❗ 아직은 로컬 list 기준으로 통계를 계산하는 상태 (UI 유지)
    final double totalDistance =
        list.fold(0.0, (a, b) => a + b.distanceKm);
    final int totalRuns = list.length;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${_focusedDay.year}년 ${_focusedDay.month}월",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "총 ${totalDistance.toStringAsFixed(2)} km 뛰었어요!",
              style: const TextStyle(
                fontSize: 20,
                color: Colors.green,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _summaryRow("러닝 횟수", "$totalRuns회"),
            // 나중에 서버 summary(_monthlySummary)를 여기로 바꿔 줄 예정
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 날짜별 상세 기록 ----------------
  Widget _buildDailyDetail(List<run_storage.RunRecord> list) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 20),
        itemBuilder: (context, i) {
          final r = list[i];
          final timeText =
              "${r.date.hour.toString().padLeft(2, '0')}:${r.date.minute.toString().padLeft(2, '0')}";

          return Row(
            children: [
              const Icon(Icons.directions_run, color: Colors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                "${r.distanceKm.toStringAsFixed(1)} km  |  $timeText",
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}
