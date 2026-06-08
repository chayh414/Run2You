// lib/services/auth_services.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ⭐ 카카오 로그인 SDK 추가
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../config.dart';

// JWT 관리 키
const String _tokenKey = 'token';

// =========================
// 🗝️ JWT 토큰 관리 헬퍼 함수
// =========================

// 1. JWT 토큰 가져오기
Future<String?> getJwtToken() async {
  final prefs = await SharedPreferences.getInstance();

  final token = prefs.getString(_tokenKey) ?? "";

  if (token.isEmpty) {
    debugPrint("⚡️ [AUTH] SharedPreferences에 저장된 토큰이 없습니다.");
    return null;
  }

  debugPrint("⚡️ [AUTH] Loaded token length: ${token.length}");

  if (token.length < 160) {
    debugPrint("🚨 WARNING: Token is too short (${token.length}자).");
  }

  return token;
}

// 2. JWT 저장
Future<void> saveJwtToken(String rawToken) async {
  final prefs = await SharedPreferences.getInstance();

  final String token = rawToken.toString().trim();

  await prefs.setString(_tokenKey, token);
  debugPrint("🔥 Saved JWT length: ${token.length}");
}

// 3. JWT 삭제
Future<void> deleteJwtToken() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_tokenKey);
  debugPrint("❌ JWT 토큰 삭제 완료");
}

// =========================
// 👤 사용자 정보 DTO
// =========================

class UserInfo {
  final String email;
  final String nickname;
  final bool emailVerified;
  final bool kakaoUser;

  UserInfo({
    required this.email,
    required this.nickname,
    required this.emailVerified,
    required this.kakaoUser,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      email: json['email'] ?? 'unknown@email.com',
      nickname: json['nickname'] ?? '사용자',
      emailVerified: json['emailVerified'] ?? false,
      kakaoUser: json['kakaoUser'] ?? false,
    );
  }
}

// =========================
// 🛡️ 인증 헤더
// =========================

// JSON API용 (기존)
Future<Map<String, String>> getAuthHeaders() async {
  final token = await getJwtToken();

  if (token == null) {
    debugPrint('⚠️ [AUTH] getAuthHeaders: 토큰 없음 → 빈 헤더 반환');
    return {
      'Content-Type': 'application/json',
    };
  }

  return {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
}

// =========================
// 🔑 Auth 공용 API
// =========================

// 로그인 API
Future<Map<String, dynamic>?> loginApi({
  required String email,
  required String password,
}) async {
  debugPrint('🔐 login baseUrl = $baseUrl');
  final url = Uri.parse('$baseUrl/api/auth/login');
  debugPrint('🔐 login URL = $url');

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    debugPrint('🔐 login status: ${response.statusCode}');
    debugPrint('🔐 login body: ${response.body}');

    final decoded = response.body.isNotEmpty
        ? jsonDecode(utf8.decode(response.bodyBytes))
        : null;

    if (response.statusCode == 200 &&
        decoded != null &&
        decoded['success'] == true &&
        decoded['token'] != null) {
      await saveJwtToken(decoded['token']);
    }

    return {
      'statusCode': response.statusCode,
      'body': decoded,
    };
  } catch (e) {
    debugPrint('❌ loginApi error: $e');
    return null;
  }
}

// 회원가입 API
Future<Map<String, dynamic>?> signUpApi({
  required String email,
  required String password,
  required String nickname,
}) async {
  debugPrint('🧾 signup baseUrl = $baseUrl');
  final url = Uri.parse('$baseUrl/api/auth/signup');
  debugPrint('🧾 signup URL = $url');

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'nickname': nickname,
      }),
    );

    debugPrint('🧾 signup status: ${response.statusCode}');
    debugPrint('🧾 signup body: ${response.body}');

    final decoded = response.body.isNotEmpty
        ? jsonDecode(utf8.decode(response.bodyBytes))
        : null;

    return {
      'statusCode': response.statusCode,
      'body': decoded,
    };
  } catch (e) {
    debugPrint('❌ signUpApi error: $e');
    return null;
  }
}

// 인증메일 재발송
Future<Map<String, dynamic>?> resendVerificationApi({
  required String email,
}) async {
  final url = Uri.parse('$baseUrl/api/auth/resend-verification');

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    debugPrint('📧 resend status: ${response.statusCode}');
    debugPrint('📧 resend body: ${response.body}');

    final decoded = response.body.isNotEmpty
        ? jsonDecode(utf8.decode(response.bodyBytes))
        : null;

    return {
      'statusCode': response.statusCode,
      'body': decoded,
    };
  } catch (e) {
    debugPrint('❌ resendVerificationApi error: $e');
    return null;
  }
}

// =========================
// ⚙️ 계정 설정 API (인증 필요)
// =========================

Future<UserInfo> fetchUserInfo() async {
  final headers = await getAuthHeaders();
  final url = Uri.parse('$baseUrl/api/users/me');

  if (!headers.containsKey('Authorization')) {
    throw Exception('사용자 정보를 불러올 수 없습니다: 인증 토큰 누락');
  }

  final getHeaders = {
    'Authorization': headers['Authorization']!,
  };

  final response = await http.get(url, headers: getHeaders);

  if (response.statusCode == 200) {
    final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
    if (jsonResponse['success'] == true) {
      return UserInfo.fromJson(jsonResponse);
    } else {
      throw Exception(jsonResponse['message'] ?? '사용자 정보를 불러올 수 없습니다.');
    }
  } else {
    throw Exception('서버 오류 (${response.statusCode}): 사용자 정보 로딩 실패');
  }
}

// =========================
// ⭐⭐ 카카오 로그인 기능 추가 ⭐⭐
// =========================

Future<Map<String, dynamic>?> kakaoLoginApi(String accessToken) async {
  try {
    final url = Uri.parse('$baseUrl/api/auth/login/kakao');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"accessToken": accessToken}),
    );

    debugPrint("📌 카카오 로그인 응답: ${response.body}");

    final decoded = jsonDecode(response.body);

    if (decoded['token'] != null) {
      await saveJwtToken(decoded['token']);
      debugPrint("🔥 카카오 로그인 → JWT 저장됨");
    }

    return {
      "statusCode": response.statusCode,
      "body": decoded,
    };
  } catch (e) {
    debugPrint("❌ kakaoLoginApi 실패: $e");
    return null;
  }
}

// =========================
// 기타 정보 수정 / 탈퇴 API
// =========================

// 닉네임 변경
Future<void> updateNickname({
  required String currentEmail,
  required String newNickname,
}) async {
  final headers = await getAuthHeaders();

  if (!headers.containsKey('Authorization')) {
    throw Exception('닉네임 변경 실패: 인증 토큰 누락');
  }

  final url = Uri.parse('$baseUrl/api/users/me');

  final response = await http.put(
    url,
    headers: headers,
    body: jsonEncode({
      "email": currentEmail,
      "nickname": newNickname
    }),
  );

  if (response.statusCode != 200) {
    throw Exception('닉네임 변경 실패');
  }
}

// 이메일 변경
Future<void> updateEmail({
  required String currentNickname,
  required String newEmail,
}) async {
  final headers = await getAuthHeaders();

  if (!headers.containsKey('Authorization')) {
    throw Exception('이메일 변경 실패: 인증 토큰 누락');
  }

  final url = Uri.parse('$baseUrl/api/users/me');

  final response = await http.put(
    url,
    headers: headers,
    body: jsonEncode({
      "email": newEmail,
      "nickname": currentNickname
    }),
  );

  if (response.statusCode != 200) {
    throw Exception('이메일 변경 실패');
  }
}

// 비밀번호 변경
Future<void> updatePassword({
  required String currentPassword,
  required String newPassword,
}) async {
  final headers = await getAuthHeaders();

  if (!headers.containsKey('Authorization')) {
    throw Exception('비밀번호 변경 실패: 인증 토큰 누락');
  }

  final url = Uri.parse('$baseUrl/api/users/me/password');

  final response = await http.put(
    url,
    headers: headers,
    body: jsonEncode({
      "currentPassword": currentPassword,
      "newPassword": newPassword
    }),
  );

  if (response.statusCode != 200) {
    throw Exception('비밀번호 변경 실패');
  }
}

// 회원 탈퇴
Future<void> deleteAccount() async {
  final headers = await getAuthHeaders();

  if (!headers.containsKey('Authorization')) {
    throw Exception('회원 탈퇴 실패: 인증 토큰 누락');
  }

  final deleteHeaders = {
    'Authorization': headers['Authorization']!,
  };

  final url = Uri.parse('$baseUrl/api/users/me');

  final response = await http.delete(url, headers: deleteHeaders);

  if (response.statusCode != 200) {
    throw Exception('회원 탈퇴 실패');
  }
}

// Multipart 인증 헤더
Future<Map<String, String>> getMultipartAuthHeaders() async {
  final token = await getJwtToken();

  if (token == null || token.isEmpty) {
    debugPrint('⚠️ [AUTH] getMultipartAuthHeaders: 인증 토큰 없음');
    return {};
  }

  return {
    'Authorization': 'Bearer $token',
  };
}

// 🔐 공통 로그인 체크 함수
Future<bool> requireLogin(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');

  if (token != null && token.isNotEmpty) {
    return true;
  }

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('로그인이 필요합니다'),
        content: const Text('이 기능은 로그인 후 이용할 수 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      );
    },
  );

  return false;
}
