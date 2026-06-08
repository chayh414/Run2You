// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

// [필수 임포트] auth_services.dart의 전역 함수와 UserInfo DTO를 사용합니다.
import '../services/auth_services.dart';
// [필수 임포트] 문의하기 서비스 임포트
import '../services/inquiry_service.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 사용자 정보 상태 (초기값은 null)
  UserInfo? _userInfo;
  bool _isLoading = true;

  // 문의하기 입력 필드 컨트롤러
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  // 파일 첨부 상태 관리 변수
  XFile? _pickedFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
  }

  // 사용자 정보 조회 함수 (GET /api/users/me)
  Future<void> _fetchUserInfo() async {
    try {
      // [전역 함수 호출]: fetchUserInfo (AuthService. 제거 완료)
      final info = await fetchUserInfo();
      setState(() {
        _userInfo = info;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('사용자 정보 로딩 실패: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용자 정보를 불러오는 데 실패했습니다. 토큰이 만료되었을 수 있습니다.')),
      );
    }
  }

  // 폰 앨범에서 이미지를 선택하는 함수
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _pickedFile = image;
      });
    }
  }

  // 문의 전송 함수 (최종 API 연동 로직)
  Future<void> _sendInquiry() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 모두 입력해 주세요.')),
      );
      return;
    }

    try {
      // 💡 [수정] 실제 InquiryService.sendInquiry 로직 호출
      await sendInquiry(
        title: title,
        content: content,
        file: _pickedFile,
      );

      // 성공 메시지
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문의가 정상적으로 접수되었습니다. 감사합니다.')),
      );

      // 입력 필드 초기화
      _titleController.clear();
      _contentController.clear();
      setState(() {
        _pickedFile = null;
      });
    } catch (e) {
      // 실패 메시지
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('문의 전송에 실패했습니다: ${e.toString()}')),
      );
    }
  }

  // 입력 필드에 사용할 테두리 디자인 함수
  InputDecoration _buildInputDecoration(String hintText, {bool isPassword = false}) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.green, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // 비밀번호 필드에만 아이콘 추가 (선택 사항)
      suffixIcon: isPassword ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey) : null,
    );
  }

  // [구현] 닉네임 변경 다이얼로그
  Future<void> _showNicknameChangeDialog() async {
    // [Null Safety 적용]: _userInfo가 null이면 함수를 즉시 종료
    if (_userInfo == null) return;

    TextEditingController controller = TextEditingController(text: _userInfo!.nickname); // 현재 닉네임 미리 채우기

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('닉네임 변경'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [Null Safety 적용]: 이미 상단에서 null 체크를 했으므로 ! 사용 안전
              Text(
                '현재 닉네임: ${_userInfo!.nickname}',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              Text(
                '♡변경된 닉네임은 재로그인시 반영됩니다♡',
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                decoration: _buildInputDecoration('새로운 닉네임을 입력하세요'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                final newNickname = controller.text.trim();
                if (newNickname.isNotEmpty && newNickname != _userInfo!.nickname) {
                  Navigator.pop(context);
                  await _handleNicknameUpdate(newNickname);
                } else if (newNickname.isNotEmpty && newNickname == _userInfo!.nickname) {
                  Navigator.pop(context);
                }
              },
              child: const Text('변경', style: TextStyle(color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  // 닉네임 변경 API 처리 로직 (PUT /api/users/me)
  Future<void> _handleNicknameUpdate(String newNickname) async {
    // [Null Safety 적용]: _userInfo가 null이면 함수를 즉시 종료
    if (_userInfo == null) return;
    try {
      // [전역 함수 호출]: updateNickname (AuthService. 제거 완료)
      await updateNickname(
        currentEmail: _userInfo!.email,
        newNickname: newNickname,
      );
      await _fetchUserInfo();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('닉네임이 성공적으로 변경되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('닉네임 변경 실패: ${e.toString()}')),
      );
    }
  }


  // [구현] 이메일 변경 다이얼로그
  Future<void> _showEmailChangeDialog() async {
    // [Null Safety 적용]: _userInfo가 null이거나 카카오 유저면 함수를 즉시 종료
    if (_userInfo == null || _userInfo!.kakaoUser) return;

    TextEditingController controller = TextEditingController(text: _userInfo!.email);

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('이메일 변경'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [Null Safety 적용]: 이미 상단에서 null 체크를 했으므로 ! 사용 안전
              Text(
                '현재 이메일: ${_userInfo!.email}',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                decoration: _buildInputDecoration('새로운 이메일을 입력하세요'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                final newEmail = controller.text.trim();
                if (newEmail.isNotEmpty) {
                  Navigator.pop(context);
                  await _handleEmailUpdate(newEmail);
                }
              },
              child: const Text('변경', style: TextStyle(color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  // 이메일 변경 API 처리 로직 (PUT /api/users/me)
  Future<void> _handleEmailUpdate(String newEmail) async {
    // [Null Safety 적용]: _userInfo가 null이면 함수를 즉시 종료
    if (_userInfo == null) return;
    try {
      // [전역 함수 호출]: updateEmail (AuthService. 제거 완료)
      await updateEmail(
        currentNickname: _userInfo!.nickname,
        newEmail: newEmail,
      );

      // 성공 시 처리 로직: 인증 메일 확인 안내 및 로그아웃 권장
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일이 변경되었습니다. 새 이메일로 인증 메일을 확인해주세요.')),
      );

      // [전역 함수 호출]: deleteJwtToken (AuthService. 제거 완료)
      await deleteJwtToken();
      // TODO: 로그인 화면으로 이동 로직 추가 (예: Navigator.pushAndRemoveUntil)

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이메일 변경 실패: ${e.toString()}')),
      );
    }
  }


  // [구현] 비밀번호 변경 다이얼로그
  Future<void> _showPasswordChangeDialog() async {
    // [Null Safety 적용]: _userInfo가 null이거나 카카오 유저면 함수를 즉시 종료
    if (_userInfo == null || _userInfo!.kakaoUser) return;

    TextEditingController currentPwController = TextEditingController();
    TextEditingController newPwController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('비밀번호 변경'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '변경할 비밀번호를 입력해주세요. (8~16자 영문 대소문자, 숫자)',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: currentPwController,
                obscureText: true,
                decoration: _buildInputDecoration('현재 비밀번호', isPassword: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPwController,
                obscureText: true,
                decoration: _buildInputDecoration('새 비밀번호', isPassword: true),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                final currentPw = currentPwController.text.trim();
                final newPw = newPwController.text.trim();
                if (currentPw.isNotEmpty && newPw.isNotEmpty) {
                  Navigator.pop(context);
                  await _handlePasswordUpdate(currentPw, newPw);
                }
              },
              child: const Text('변경', style: TextStyle(color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  // 비밀번호 변경 API 처리 로직 (PUT /api/users/me/password)
  Future<void> _handlePasswordUpdate(String currentPassword, String newPassword) async {
    try {
      // [전역 함수 호출]: updatePassword (AuthService. 제거 완료)
      await updatePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 성공적으로 변경되었습니다.')),
      );
      // TODO: 비밀번호 변경 후 로그아웃 처리 (deleteJwtToken)
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('비밀번호 변경 실패: ${e.toString()}')),
      );
    }
  }


  // [구현] 회원 탈퇴 다이얼로그 (DELETE /api/users/me)
  Future<void> _showWithdrawDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('회원 탈퇴'),
          content: const Text('정말로 회원 탈퇴를 진행하시겠습니까? 모든 데이터는 삭제되며 복구할 수 없습니다.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _handleAccountDeletion();
              },
              child: const Text('탈퇴', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  // 회원 탈퇴 API 처리 로직
  Future<void> _handleAccountDeletion() async {
    try {
      // [전역 함수 호출]: deleteAccount (AuthService. 제거 완료)
      await deleteAccount();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원 탈퇴가 완료되었습니다. 모든 데이터가 삭제되었습니다.')),
      );

      // [전역 함수 호출]: deleteJwtToken (AuthService. 제거 완료)
      await deleteJwtToken();
      // TODO: 로그인 화면으로 이동 로직 추가 (예: Navigator.pushAndRemoveUntil)

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('회원 탈퇴 실패: ${e.toString()}')),
      );
    }
  }


  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    // 💡 [Null Safety 강화]: 로딩이 끝났는데도 _userInfo가 null이면 에러 화면을 표시합니다.
    if (_userInfo == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black), onPressed: () => Navigator.pop(context)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Text(
              '회원 정보를 불러올 수 없습니다. 다시 로그인하거나 앱을 재시작해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ),
      );
    }

    // _userInfo가 null이 아님을 확인했으므로 이제 안전하게 접근합니다.
    final bool isKakaoUser = _userInfo!.kakaoUser;
    final double inputWidth = MediaQuery.of(context).size.width - 150;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '설정',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // --- 섹션 1: 계정 설정 ---
            const Text(
              '계정 설정',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildSectionContainer(
              children: [
                // 닉네임 변경
                _buildListTile(
                  '닉네임 변경',
                  onTap: _showNicknameChangeDialog,
                  // [Null Safety 적용]: _userInfo! 사용
                  subtitle: '현재 닉네임: ${_userInfo!.nickname}',
                ),
                _buildDivider(),

                // 이메일 변경: 카카오 유저는 비활성화
                _buildListTile(
                  '이메일 변경',
                  onTap: isKakaoUser ? null : _showEmailChangeDialog,
                  // [Null Safety 적용]: _userInfo! 사용
                  subtitle: isKakaoUser ? '카카오 로그인 유저는 변경 불가' : '현재 이메일: ${_userInfo!.email}',
                  isEnabled: !isKakaoUser,
                ),
                _buildDivider(),

                // 비밀번호 변경: 카카오 유저는 비활성화
                _buildListTile(
                  '비밀번호 변경',
                  onTap: isKakaoUser ? null : _showPasswordChangeDialog,
                  subtitle: isKakaoUser ? '카카오 로그인 유저는 변경 불가' : '비밀번호를 변경합니다',
                  isEnabled: !isKakaoUser,
                ),
                _buildDivider(),

                // 탈퇴하기
                _buildListTile('탈퇴하기', onTap: _showWithdrawDialog),
              ],
            ),

            const SizedBox(height: 30),

            // --- 섹션 2: 문의하기 ---
            const Text(
              '문의하기',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildSectionContainer(
              children: [
                // 제목 입력
                _buildListTile(
                  '제목',
                  showArrow: false,
                  titleWidth: 50,
                  trailingWidget: SizedBox(
                    width: inputWidth,
                    child: TextField(
                      controller: _titleController,
                      style: const TextStyle(fontSize: 14),
                      decoration: _buildInputDecoration('제목을 입력하세요'),
                    ),
                  ),
                ),
                _buildDivider(),

                // 내용 입력
                _buildListTile(
                  '내용',
                  showArrow: false,
                  titleWidth: 50,
                  trailingWidget: SizedBox(
                    width: inputWidth,
                    child: TextField(
                      controller: _contentController,
                      style: const TextStyle(fontSize: 14),
                      decoration: _buildInputDecoration('내용을 입력하세요'),
                    ),
                  ),
                ),
                _buildDivider(),

                // 파일 선택
                const Padding(
                  padding: EdgeInsets.only(left: 16.0, right: 10.0, top: 12.0, bottom: 4.0),
                  child: Row(
                    children: [
                      Icon(Icons.directions_run, color: Colors.grey, size: 24),
                      SizedBox(width: 10),
                      Text(
                        '파일 첨부 (선택)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),


                // 파일 첨부 박스
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      // [Null Safety 적용]: _pickedFile이 null일 수 있으므로 ? 사용
                      image: _pickedFile != null ? DecorationImage(
                        image: FileImage(File(_pickedFile!.path)),
                        fit: BoxFit.cover,
                      ) : null,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_pickedFile == null)
                            ElevatedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.attachment, size: 18),
                              label: const Text('첨부하기'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                side: const BorderSide(color: Colors.grey),
                              ),
                            ),

                          if (_pickedFile == null)
                            const SizedBox(height: 8),

                          if (_pickedFile != null)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                _pickedFile!.name,
                                style: const TextStyle(color: Colors.white, backgroundColor: Colors.black54),
                                textAlign: TextAlign.center,
                              ),
                            ),

                          if (_pickedFile != null)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _pickedFile = null;
                                });
                              },
                              child: const Text('삭제', style: TextStyle(color: Colors.red)),
                            ),

                          if (_pickedFile == null)
                            Text(
                              '이미지 파일을 첨부하세요',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 문의 전송 버튼
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: ElevatedButton(
                    onPressed: _sendInquiry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('문의 전송', style: TextStyle(color: Colors.white)),
                  ),
                ),

              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      
    );
  }

  // 흰색 둥근 배경 컨테이너 위젯
  Widget _buildSectionContainer({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  // 리스트 아이템 위젯: subtitle, isEnabled 파라미터 추가
  Widget _buildListTile(
      String title, {
        bool showArrow = true,
        VoidCallback? onTap,
        Widget? trailingWidget,
        double? titleWidth,
        String? subtitle,
        bool isEnabled = true,
      }) {
    // 비활성화 상태일 때 아이콘/글자 색상
    final Color color = isEnabled ? Colors.black : Colors.grey.withOpacity(0.5);
    final Color iconColor = isEnabled ? Colors.grey : Colors.grey.withOpacity(0.5);

    return ListTile(
      // 🏃 달리는 사람 아이콘으로 최종 적용
      leading: Icon(
          Icons.directions_run,
          color: iconColor
      ),
      title: SizedBox(
        width: titleWidth,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      // 서브타이틀이 있을 경우 표시
      subtitle: subtitle != null
          ? Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: iconColor),
      )
          : null,

      trailing: trailingWidget ?? (showArrow
          ? Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: iconColor,
      )
          : null),

      onTap: isEnabled ? onTap : null, // 비활성화 시 onTap 막기
      contentPadding: const EdgeInsets.only(left: 16, right: 10),
    );
  }

  // 구분선 위젯
  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16);
  }
}