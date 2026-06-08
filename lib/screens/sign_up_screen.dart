// lib/screens/sign_up_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/policy_footer.dart';
import 'terms_of_service_screen.dart';
import 'privacy_policy_screen.dart';

import '../services/auth_services.dart';
import '../utils/storage.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';

/// 회원가입 단계
enum SignUpStep {
  email,
  password,
  nickname,
  waitEmailVerify,
  complete,
  welcome,
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  SignUpStep _step = SignUpStep.email;

  // 컨트롤러
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();

  // 입력값 캐싱
  String? _email;
  String? _password;
  String? _nickname;

  // 에러 메시지
  String? _emailError;
  String? _passwordError;
  String? _nicknameError;

  bool _isLoading = false;

  // ----------------------------
  // 공통 유효성 검사
  // ----------------------------
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    return emailRegex.hasMatch(email);
  }

  bool _isValidPassword(String pw) {
    // 8~16자, 영문 대소문자 + 숫자
    final pwRegex = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,16}$');
    return pwRegex.hasMatch(pw);
  }

  // ----------------------------
  // 1) 이메일 단계 처리
  // ----------------------------
  Future<void> _goNextFromEmail() async {
    final email = _emailController.text.trim();

    setState(() {
      _emailError = null;
    });

    if (email.isEmpty || !_isValidEmail(email)) {
      setState(() {
        _emailError = '올바른 이메일 형식을 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _email = email;
      _step = SignUpStep.password;
    });
  }

  // ----------------------------
  // 2) 비밀번호 단계 처리
  // ----------------------------
  Future<void> _goNextFromPassword() async {
    final pw = _passwordController.text.trim();

    setState(() {
      _passwordError = null;
    });

    if (!_isValidPassword(pw)) {
      setState(() {
        _passwordError = '비밀번호를 형식에 맞게 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _password = pw;
      _step = SignUpStep.nickname;
    });
  }

  // ----------------------------
  // 3) 닉네임 단계 처리
  // ----------------------------
  Future<void> _goNextFromNickname() async {
    final nickname = _nicknameController.text.trim();

    setState(() {
      _nicknameError = null;
    });

    if (nickname.isEmpty) {
      setState(() {
        _nicknameError = '닉네임을 입력해 주세요.';
      });
      return;
    }

    // 프론트 단에서만 임시 중복 체크 (대소문자 무시)
    const usedNicknames = <String>['runner', 'admin', 'test'];
    if (usedNicknames
        .map((e) => e.toLowerCase())
        .contains(nickname.toLowerCase())) {
      setState(() {
        _nicknameError = '이미 사용 중인 닉네임입니다.';
      });
      return;
    }

    // 서버로 회원가입 요청
    if (_email == null || _password == null) return;

    setState(() => _isLoading = true);

    try {
      final result = await signUpApi(
        email: _email!,
        password: _password!,
        nickname: nickname,
      );

      if (result == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버와 통신 중 오류가 발생했습니다.')),
        );
        return;
      }

      final statusCode = result['statusCode'] as int? ?? 0;
      final body = (result['body'] as Map<String, dynamic>?) ?? {};
      final success = body['success'] == true;
      final message =
          body['message']?.toString() ?? '회원가입에 실패했습니다. 다시 시도해 주세요.';

      if (statusCode == 200 && success) {
        setState(() {
          _nickname = nickname;
          _step = SignUpStep.waitEmailVerify;
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      debugPrint('❌ signUp error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알 수 없는 오류가 발생했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ----------------------------
  // 4) 이메일 인증 대기 단계
  // ----------------------------
  Future<void> _resendEmail() async {
    if (_email == null) return;

    setState(() => _isLoading = true);

    try {
      final result = await resendVerificationApi(email: _email!);

      if (result == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재발송에 실패했습니다. 다시 시도해 주세요.')),
        );
        return;
      }

      final body = (result['body'] ?? {}) as Map<String, dynamic>;
      final msg = body['message']?.toString() ?? '인증 메일을 다시 보냈어요!';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      debugPrint('❌ resend error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재발송 중 오류가 발생했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 사용자가 "인증 완료" 버튼을 눌렀다고 가정하고,
  /// 바로 완료 화면으로 이동 (실제 인증 여부는 백엔드에서 체크해야 함)
  Future<void> _onEmailVerified() async {
    setState(() {
      _step = SignUpStep.complete;
    });

    // 2초 후 환영 화면 -> 자동 로그인 -> 홈 이동
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _step = SignUpStep.welcome;
    });

    // 여기서 자동 로그인 + 토큰 저장
    if (_email != null && _password != null) {
      try {
        final result = await loginApi(email: _email!, password: _password!);
        if (result != null) {
          final body = (result['body'] as Map<String, dynamic>?) ?? {};
          if (body['success'] == true) {
            await saveAuthInfo(body);
          }
        }
      } catch (e) {
        debugPrint('❌ auto login after signup error: $e');
      }
    }

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  // ----------------------------
  // UI 공통: 상단 AppBar 영역
  // ----------------------------
  PreferredSizeWidget _buildSimpleAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
        onPressed: () {
          if (_step == SignUpStep.email) {
            Navigator.of(context).pop();
          } else if (_step == SignUpStep.password) {
            setState(() => _step = SignUpStep.email);
          } else if (_step == SignUpStep.nickname) {
            setState(() => _step = SignUpStep.password);
          } else if (_step == SignUpStep.waitEmailVerify) {
            setState(() => _step = SignUpStep.nickname);
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }

  // ----------------------------
  // 1) 이메일 입력 화면
  // ----------------------------
  Widget _buildEmailStep(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildSimpleAppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Image.asset(
                  "assets/R2U_logo.png",
                  width: 96,
                  height: 96,
                ),
                const SizedBox(height: 24),
                const Text(
                  "계정 만들기",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "앱에 가입하려면 이메일을 입력하세요.",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: "email@domain.com",
                    errorText: _emailError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF34A853),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // ✅ 여기 버튼만 3D 느낌으로 스타일 변경
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34A853),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0x8034A853),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _goNextFromEmail,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            "계속",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const PolicyFooter(),

              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const _SignUpBottomNavBar(),
    );
  }

  // ----------------------------
  // 2) 비밀번호 입력 화면
  // ----------------------------
  Widget _buildPasswordStep(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildSimpleAppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Image.asset(
                  "assets/R2U_logo.png",
                  width: 96,
                  height: 96,
                ),
                const SizedBox(height: 24),
                const Text(
                  "계정 만들기",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "사용하려는 비밀번호를 입력해 주세요.",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "비밀번호",
                    errorText: _passwordError,
                    helperText: "  * 8~16자 영문 대·소문자, 숫자를 사용하세요.",
                    helperStyle: const TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF34A853),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34A853),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0x8034A853),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _goNextFromPassword,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            "계속",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const PolicyFooter(), // 서비스 이용 약관 및 개인정보 처리방침 페이지
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const _SignUpBottomNavBar(),
    );
  }

  // ----------------------------
  // 3) 닉네임 입력 화면
  // ----------------------------
  Widget _buildNicknameStep(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildSimpleAppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Image.asset(
                  "assets/R2U_logo.png",
                  width: 96,
                  height: 96,
                ),
                const SizedBox(height: 24),
                const Text(
                  "계정 만들기",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "사용하려는 닉네임을 입력해 주세요.",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nicknameController,
                  decoration: InputDecoration(
                    hintText: "예) 러너지윤",
                    errorText: _nicknameError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF34A853),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34A853),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0x8034A853),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _goNextFromNickname,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            "계속",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const PolicyFooter(), // 서비스 이용 약관 및 개인정보 처리방침 페이지
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const _SignUpBottomNavBar(),
    );
  }

  // ----------------------------
  // 4) 이메일 인증 안내 화면
  // ----------------------------
  Widget _buildWaitEmailVerifyStep(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildSimpleAppBar(),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  "assets/R2U_logo.png",
                  width: 96,
                  height: 96,
                ),
                const SizedBox(height: 24),
                const Text(
                  "계정 만들기",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "이메일 인증을 완료해주세요.",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF34A853),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _email ?? "",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "스팸메일함도 꼭 확인해 주세요!",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFF34A853),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _isLoading ? null : _onEmailVerified,
                          child: const Text(
                            "인증 완료",
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF34A853),
                            foregroundColor: const Color(0xFFFFFFFF),
                            elevation: 0,
                            side: const BorderSide(
                              color: Color(0xFF34A853),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _isLoading ? null : _resendEmail,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                      Color(0xFF34A853),
                                    ),
                                  ),
                                )
                              : const Text(
                                  "이메일 재발송",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const _SignUpBottomNavBar(),
    );
  }

  // ----------------------------
  // 5) 가입 완료 화면
  // ----------------------------
  Widget _buildCompleteStep(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildSimpleAppBar(),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                "assets/R2U_logo.png",
                width: 96,
                height: 96,
              ),
              const SizedBox(height: 24),
              const Text(
                "계정 만들기",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                "가입이 완료되었습니다!",
                style: TextStyle(
                  fontSize: 18,
                  color: Color(0xFF34A853),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const _SignUpBottomNavBar(),
    );
  }

  // ----------------------------
  // 6) 환영 메시지 화면
  // ----------------------------
  Widget _buildWelcomeStep(BuildContext context) {
    final nickname = _nickname ?? '러너';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildSimpleAppBar(),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                "assets/R2U_logo.png",
                width: 96,
                height: 96,
              ),
              const SizedBox(height: 24),
              const Text(
                "계정 만들기",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              Text(
                "$nickname님! R2U와 함께 안전하게 달려볼까요?",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF34A853),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const _SignUpBottomNavBar(),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case SignUpStep.email:
        return _buildEmailStep(context);
      case SignUpStep.password:
        return _buildPasswordStep(context);
      case SignUpStep.nickname:
        return _buildNicknameStep(context);
      case SignUpStep.waitEmailVerify:
        return _buildWaitEmailVerifyStep(context);
      case SignUpStep.complete:
        return _buildCompleteStep(context);
      case SignUpStep.welcome:
        return _buildWelcomeStep(context);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }
}

/// 하단 탭바 (로그인 화면과 동일하게 보이도록)
class _SignUpBottomNavBar extends StatelessWidget {
  const _SignUpBottomNavBar();

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      selectedItemColor: const Color(0xFF34A853),
      unselectedItemColor: Colors.grey,
      onTap: (index) {
        if (index == 0) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        } else if (index == 1) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: '로그인',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: '홈',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today),
          label: '캘린더',
        ),
      ],
    );
  }
}
