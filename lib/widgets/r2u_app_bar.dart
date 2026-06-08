// lib/widgets/r2u_app_bar.dart

import 'package:flutter/material.dart';

/// ✅ 공용 AppBar (로고만 가운데 표시)
class R2UAppBar extends StatelessWidget implements PreferredSizeWidget {
  const R2UAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      title: Image.asset(
        'assets/R2U_logo.png',
        height: 28,
        fit: BoxFit.contain,
      ),
    );
  }
}
