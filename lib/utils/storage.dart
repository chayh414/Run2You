// lib/utils/storage.dart
import 'package:shared_preferences/shared_preferences.dart';

/// 🔐 로그인 정보 저장
/// 서버에서 받은 body 그대로 넣어주면 됨
Future<void> saveAuthInfo(Map<String, dynamic> body) async {
  final prefs = await SharedPreferences.getInstance();

  final token = body['token']?.toString();
  final email = body['email']?.toString();
  // 서버에서 nickname / nickName / userNickname 등 뭐로 줄지 몰라서 다 체크
  final nickname =
      body['nickname']?.toString() ??
      body['nickName']?.toString() ??
      body['userNickname']?.toString();

  final userIdRaw = body['userId'];

  if (token != null && token.isNotEmpty) {
    await prefs.setString('token', token);
  }
  if (email != null && email.isNotEmpty) {
    await prefs.setString('email', email);
  }
  if (nickname != null && nickname.isNotEmpty) {
    await prefs.setString('nickname', nickname);
  }
  if (userIdRaw != null) {
    int? userId;
    if (userIdRaw is int) {
      userId = userIdRaw;
    } else {
      userId = int.tryParse(userIdRaw.toString());
    }
    if (userId != null) {
      await prefs.setInt('userId', userId);
    }
  }
}

/// 🔐 현재 로그인되어 있는지 (토큰 기준)
Future<bool> isLoggedIn() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  return token != null && token.isNotEmpty;
}

/// 🔐 저장된 닉네임 가져오기
Future<String?> getSavedNickname() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('nickname');
}

/// 🔐 저장된 이메일 가져오기
Future<String?> getSavedEmail() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('email');
}