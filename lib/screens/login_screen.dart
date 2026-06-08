// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_services.dart';
import '../utils/storage.dart';
import '../widgets/social_button.dart';
import 'sign_up_screen.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart'; // ✅ 카카오 SDK

/// 🔹 로그인 + 마이페이지 화면
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 이메일 / 비밀번호 컨트롤러
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;

  // ✅ 로그인 상태 / 유저 정보
  bool _isLoggedIn = false;
  String? _nickname;
  String? _email;

  @override
  void initState() {
    super.initState();
    _loadAuthInfo(); // 앱 켤 때 저장된 토큰/닉네임 불러오기 → 자동 로그인
  }

  /// 💾 SharedPreferences 에서 로그인 정보 불러오기 (자동 로그인)
  Future<void> _loadAuthInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final nickname = prefs.getString('nickname');
    final email = prefs.getString('email');

    if (token != null && token.isNotEmpty) {
      // 닉네임 없을 때 대비: 이메일이라도 보여주기
      setState(() {
        _isLoggedIn = true;
        _nickname = nickname ?? email ?? '러너';
        _email = email;
      });
      debugPrint('🔑 저장된 로그인 상태 복원됨: $_nickname / $_email');
    } else {
      debugPrint('ℹ️ 저장된 로그인 정보 없음 (처음 접속 또는 로그아웃 상태)'); 
    }
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    return emailRegex.hasMatch(email);
  }

  /// ✅ 이메일 인증 대기 다이얼로그 (로그인 시 아직 인증 안 됐을 때)
  void _showEmailVerificationPendingDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("이메일 인증이 필요해요"),
          content: Text(
            "$email 로 인증 메일을 보냈어요.\n메일함에서 인증 링크를 눌러주세요.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("닫기"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _resendVerification(email);
              },
              child: const Text("인증 메일 재발송"),
            ),
          ],
        );
      },
    );
  }

  /// ✅ 인증메일 재발송 실행
  Future<void> _resendVerification(String email) async {
    setState(() => _isLoading = true);

    try {
      final result = await resendVerificationApi(email: email);

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("재발송 실패(통신 오류)")),
        );
        return;
      }

      final body = (result['body'] ?? {}) as Map<String, dynamic>;
      final msg = body['message']?.toString() ?? "인증 메일을 다시 보냈어요!";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );

      // 재발송 후 다시 안내 띄우기
      _showEmailVerificationPendingDialog(email);
    } catch (e) {
      debugPrint('❌ _resendVerification error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("재발송 중 오류 발생")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 🔐 이메일/비밀번호 로그인 버튼 눌렀을 때
  Future<void> _onLoginPressed() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 비밀번호를 모두 입력해 주세요')),
      );
      return;
    }

    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 이메일 형식이 아닙니다')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await loginApi(email: email, password: password);

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버와 통신 중 오류가 발생했습니다.')),
        );
        return;
      }

      final statusCode = result['statusCode'] as int? ?? 0;
      final rawBody = (result['body'] as Map<String, dynamic>?) ?? {};
      final success = rawBody['success'] == true;
      final message =
          rawBody['message']?.toString() ?? '로그인에 실패했습니다.';

      debugPrint('🔐 login status: $statusCode');
      debugPrint('🔐 login raw body: $rawBody');

      // 🔹 실제 유저 정보가 들어있는 부분만 뽑기 (data / user / userInfo 중에 있으면 그걸 사용)
      Map<String, dynamic> userBody = rawBody;
      for (final key in ['data', 'user', 'userInfo']) {
        final val = rawBody[key];
        if (val is Map<String, dynamic>) {
          userBody = val;
          break;
        }
      }

      if (statusCode == 200 && success) {
        // ✅ 1) 토큰 / 이메일 추출 (없으면 rawBody 쪽에서도 한 번 더 시도)
        final token =
            userBody['token']?.toString() ?? rawBody['token']?.toString();
        final emailFromServer =
            userBody['email']?.toString() ?? rawBody['email']?.toString();

        // ✅ 2) 닉네임 후보 추출
        String? nicknameFromServer;
        for (final key in [
          'nickname',
          'nickName',
          'userNickname',
          'name',
          'username',
        ]) {
          final v = userBody[key] ?? rawBody[key];
          if (v is String && v.trim().isNotEmpty) {
            nicknameFromServer = v.trim();
            break;
          }
        }

        debugPrint(
            '✅ 1차 닉네임 추출: $nicknameFromServer (email: $emailFromServer)');

        // ✅ 3) 공용 저장함수로 로컬 저장 (userBody 안에 있는 값 위주)
        await saveAuthInfo(userBody);

        // ✅ 4) SharedPreferences에 토큰/이메일/닉네임 저장
        final prefs = await SharedPreferences.getInstance();
        if (token != null) {
          await prefs.setString('token', token);
        }
        if (emailFromServer != null) {
          await prefs.setString('email', emailFromServer);
        }
        if (nicknameFromServer != null && nicknameFromServer.isNotEmpty) {
          await prefs.setString('nickname', nicknameFromServer);
        }

        // ✅ 5) 여기서 한 번 더! 서버의 /api/users/me 에서 진짜 유저 정보 가져오기
        try {
          final userInfo = await fetchUserInfo();
          debugPrint(
              '✅ fetchUserInfo 결과: nickname=${userInfo.nickname}, email=${userInfo.email}');

          // fetchUserInfo 결과를 최우선으로 사용
          nicknameFromServer = userInfo.nickname.isNotEmpty
              ? userInfo.nickname
              : nicknameFromServer;

          // SharedPreferences에도 다시 한 번 저장
          await prefs.setString('nickname', nicknameFromServer ?? '');
          await prefs.setString('email', userInfo.email);
        } catch (e) {
          debugPrint('⚠️ fetchUserInfo 실패, 로그인 응답에 있는 값만 사용: $e');
        }

        // ✅ 6) 상태 업데이트 → 마이페이지 화면으로 전환
        setState(() {
          _isLoggedIn = true;
          _nickname = nicknameFromServer ?? emailFromServer ?? email;
          _email = emailFromServer ?? email;
          _emailController.clear();
          _passwordController.clear();
        });

        debugPrint('🎉 최종 닉네임: $_nickname / 이메일: $_email');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)), // "로그인 성공" 등
        );
      } else {
        // ❌ 실패 (비밀번호 불일치 / 인증 안됨 등)
        if (message == "EMAIL_NOT_VERIFIED" ||
            rawBody['code'] == "EMAIL_NOT_VERIFIED") {
          _showEmailVerificationPendingDialog(email);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ _onLoginPressed error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알 수 없는 오류가 발생했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

    /// 🔐 카카오 소셜 로그인
  Future<void> _onKakaoLoginPressed() async {
    debugPrint('🚀 [KAKAO] 버튼 onPressed 진입!');

    try {
      // 1️⃣ KakaoTalk 설치 여부 확인
      final bool talkInstalled = await isKakaoTalkInstalled();
      debugPrint('📱 isKakaoTalkInstalled = $talkInstalled');

      OAuthToken token;

      if (talkInstalled) {
        debugPrint('➡️ KakaoTalk 앱으로 로그인 시도 (loginWithKakaoTalk)');
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        debugPrint('➡️ 브라우저(계정) 로그인 시도 (loginWithKakaoAccount)');
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      // 2️⃣ 토큰 정상 수신
      debugPrint('🔥 Kakao AccessToken: ${token.accessToken}');

      // 3️⃣ 우리 서버로 토큰 전송
      final result = await kakaoLoginApi(token.accessToken);

      if (result == null) {
        debugPrint("⚠️ kakaoLoginApi result == null (서버 응답 없음)");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("카카오 로그인 실패 (서버 응답 없음)")),
        );
        return;
      }

      final statusCode = result['statusCode'] as int? ?? 0;
      final rawBody = (result['body'] ?? {}) as Map<String, dynamic>;

      debugPrint("⭐ kakaoLoginApi status: $statusCode");
      debugPrint("⭐ kakaoLoginApi body: $rawBody");

      final success = rawBody['success'] == true;
      final message =
          rawBody['message']?.toString() ?? "카카오 로그인 처리 중입니다.";

      // 4️⃣ 실제 유저 데이터만 뽑기 (data / user / userInfo 우선)
      Map<String, dynamic> userBody = rawBody;
      for (final key in ['data', 'user', 'userInfo']) {
        final val = rawBody[key];
        if (val is Map<String, dynamic>) {
          userBody = val;
          break;
        }
      }

      if (statusCode == 200 && (success || rawBody['token'] != null)) {
        // 이메일, 닉네임 후보 추출
        final emailFromServer =
            userBody['email']?.toString() ?? rawBody['email']?.toString();

        String? nicknameFromServer;
        for (final key in [
          'nickname',
          'nickName',
          'userNickname',
          'name',
          'username',
        ]) {
          final v = userBody[key] ?? rawBody[key];
          if (v is String && v.trim().isNotEmpty) {
            nicknameFromServer = v.trim();
            break;
          }
        }

        debugPrint(
            '✅ [KAKAO] 1차 닉네임 추출: $nicknameFromServer (email: $emailFromServer)');

        // 유저 정보 공용 저장
        await saveAuthInfo(userBody);

        // /users/me 로 최종 유저 정보 다시 확인
        final prefs = await SharedPreferences.getInstance();
        try {
          final userInfo = await fetchUserInfo();
          debugPrint(
              '✅ [KAKAO] fetchUserInfo 결과: nickname=${userInfo.nickname}, email=${userInfo.email}');

          nicknameFromServer = userInfo.nickname.isNotEmpty
              ? userInfo.nickname
              : nicknameFromServer;

          await prefs.setString('nickname', nicknameFromServer ?? '');
          await prefs.setString('email', userInfo.email);
        } catch (e) {
          debugPrint('⚠️ [KAKAO] fetchUserInfo 실패, 응답 값만 사용: $e');
          if (emailFromServer != null) {
            await prefs.setString('email', emailFromServer);
          }
          if (nicknameFromServer != null) {
            await prefs.setString('nickname', nicknameFromServer);
          }
        }

        // 상태 반영
        setState(() {
          _isLoggedIn = true;
          _nickname = nicknameFromServer ?? emailFromServer ?? '러너';
          _email = emailFromServer;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.isNotEmpty ? message : "카카오 로그인 성공!",
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rawBody['message']?.toString() ?? "카카오 로그인 실패",
            ),
          ),
        );
      }
    } on KakaoAuthException catch (e) {
      // 카카오 인증 에러 (사용자 취소 포함)
      debugPrint('❌ [KAKAO] KakaoAuthException: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("카카오 로그인 실패: ${e.message ?? e.toString()}")),
      );
    } on KakaoClientException catch (e) {
      // 네트워크 등 클라이언트 에러
      debugPrint('❌ [KAKAO] KakaoClientException: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("카카오 통신 오류: ${e.message ?? e.toString()}")),
      );
    } catch (e) {
      debugPrint("❌ [KAKAO] 알 수 없는 오류: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("카카오 로그인 중 알 수 없는 오류 발생")),
      );
    }
  }


  /// 🚪 로그아웃
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('email');
    await prefs.remove('nickname');

    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _nickname = null;
      _email = null;
      _emailController.clear();
      _passwordController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그아웃 되었습니다.')),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 로그인 된 상태 → 마이페이지 화면
    if (_isLoggedIn) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: Image.asset(
                  "assets/R2U_logo.png",
                  width: 140,
                  height: 140,
                ),
              ),
              Text(
                "${_nickname ?? '러너'}님, 환영합니다!",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (_email != null)
                Text(
                  _email!,
                  style: const TextStyle(color: Colors.black54),
                ),
              const SizedBox(height: 20),
              const Text(
                "R2U와 함께 안전하게 달려볼까요?",
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  onPressed: _logout,
                  child: const Text(
                    "로그아웃",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ❌ 아직 로그인 안 된 상태 → 로그인 화면
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 작은 화면에서도 스크롤 가능하도록
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ✅ 로고
                      Padding(
                        padding: const EdgeInsets.only(bottom: 40.0),
                        child: Image.asset(
                          "assets/R2U_logo.png",
                          width: 140,
                          height: 140,
                        ),
                      ),

                      const Text(
                        "로그인",
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "이메일과 비밀번호를 입력해 로그인하세요",
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 20),

                      // 이메일
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: "email@domain.com",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 비밀번호
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: "비밀번호",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      // 로그인 버튼
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          onPressed: _isLoading ? null : _onLoginPressed,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("로그인"),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // "또는"
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              thickness: 1,
                              color: Colors.grey.shade300,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              "또는",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              thickness: 1,
                              color: Colors.grey.shade300,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ⭐ 카카오 소셜 로그인 버튼
                      SocialButton(
                        text: "KAKAO 계정으로 계속하기",
                        assetName: "assets/kakao.png",
                        onPressed: _onKakaoLoginPressed,
                      ),

                      const SizedBox(height: 20),

                      // 회원가입 텍스트 버튼
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "아직 계정이 없으신가요? ",
                            style: TextStyle(color: Colors.black54),
                          ),
                          TextButton(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                PageRouteBuilder(
                                  pageBuilder: (_, animation, __) {
                                    final offsetAnimation =
                                        Tween<Offset>(
                                      begin: const Offset(1.0, 0.0),
                                      end: Offset.zero,
                                    ).animate(animation);

                                    return SlideTransition(
                                      position: offsetAnimation,
                                      child: const SignUpScreen(),
                                    );
                                  },
                                ),
                              );
                            },
                            child: const Text(
                              "회원가입",
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
