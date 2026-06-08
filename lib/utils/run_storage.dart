// lib/utils/run_storage.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 런닝 기록 모델
class RunRecord {
  final int userId; 
  final DateTime date;
  final String name;
  final double distanceKm;

  RunRecord({
    required this.userId,
    required this.date,
    required this.name,
    required this.distanceKm,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'date': date.toIso8601String(),
      'name': name,
      'distanceKm': distanceKm,
    };
  }

  factory RunRecord.fromJson(Map<String, dynamic> json) {
    return RunRecord(
      userId: json['userId'] as int,
      date: DateTime.parse(json['date'] as String),
      name: json['name'] as String,
      distanceKm: (json['distanceKm'] as num).toDouble(),
    );
  }
}

const _storageKey = 'run_records_v2';

/// 전체 기록 불러오기
Future<List<RunRecord>> loadRunRecords() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_storageKey);
  if (raw == null || raw.isEmpty) return [];

  final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
  return list
      .whereType<Map<String, dynamic>>()
      .map((m) => RunRecord.fromJson(m))
      .toList();
}

/// 특정 userId 기록만 필터링
Future<List<RunRecord>> getRecordsForUser(int userId) async {
  final all = await loadRunRecords();
  return all.where((r) => r.userId == userId).toList();
}

/// 기록 하나 추가
Future<void> addRunRecord(RunRecord record) async {
  final prefs = await SharedPreferences.getInstance();
  final current = await loadRunRecords();
  current.add(record);

  final encoded = jsonEncode(current.map((e) => e.toJson()).toList());
  await prefs.setString(_storageKey, encoded);
}
