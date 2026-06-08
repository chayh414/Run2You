// lib/services/inquiry_service.dart

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../config.dart';
import 'auth_services.dart';

/// 문의 전송 API (POST /api/support/inquiry)
/// 인증 토큰을 요구하며, 파일 첨부가 가능한 Multipart 요청입니다.
Future<void> sendInquiry({
  required String title,
  required String content,
  XFile? file,
}) async {
  debugPrint('📝 문의 전송 시작');

  // 🔥 (중요) multipart 용 인증 헤더만 사용해야 함
  final authHeaders = await getMultipartAuthHeaders();

  // 서버 API 경로
  final url = Uri.parse('$baseUrl/api/support/inquiry');
  debugPrint('➡️ 전송 URL: $url');

  // MultipartRequest 생성
  var request = http.MultipartRequest('POST', url);

  // Authorization 추가 (Content-Type 없음)
  if (authHeaders.containsKey('Authorization')) {
    final tokenValue = authHeaders['Authorization']!;
    request.headers['Authorization'] = tokenValue;

    debugPrint('🔑 Authorization 접두사: ${tokenValue.substring(0, tokenValue.length > 7 ? 7 : tokenValue.length)}');
    debugPrint('🔑 Authorization 토큰 길이: ${tokenValue.length}');
  } else {
    throw Exception('인증 토큰이 없습니다. 로그인이 필요합니다.');
  }

  // 필드 데이터 추가
  request.fields['title'] = title;
  request.fields['content'] = content;

  // 파일 첨부
  if (file != null) {
    if (!File(file.path).existsSync()) {
      debugPrint('❌ 파일 경로가 유효하지 않습니다: ${file.path}');
      throw Exception('첨부하려는 파일이 로컬 저장소에 없습니다.');
    }

    debugPrint('📎 파일 첨부: ${file.path}');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
      ),
    );
  }

  // 요청 전송
  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  debugPrint('📝 문의 전송 상태 코드: ${response.statusCode}');
  debugPrint('📝 문의 전송 응답 본문: ${response.body}');

  // 응답 처리
  if (response.statusCode == 200) {
    final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
    if (jsonResponse['success'] != true) {
      throw Exception(jsonResponse['message'] ?? '문의 전송 실패: 서버 내부 오류');
    }
    debugPrint('🎉 문의가 정상적으로 접수되었습니다.');
  } else if (response.statusCode == 401 || response.statusCode == 403) {
    throw Exception('문의 전송 실패: 인증 오류 (${response.statusCode}). 유효한 토큰인지 확인해 주세요.');
  } else if (response.statusCode == 404) {
    throw Exception('문의 전송 실패: API 경로를 찾을 수 없습니다. (${response.statusCode})');
  } else {
    throw Exception('문의 전송 실패: 서버 오류 (${response.statusCode})');
  }
}