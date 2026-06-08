// lib/widgets/social_button.dart

import 'package:flutter/material.dart';

class SocialButton extends StatelessWidget {
  final String text;
  final String assetName;
  final VoidCallback onPressed;   // ⭐ 추가됨

  const SocialButton({
    super.key,
    required this.text,
    required this.assetName,
    required this.onPressed,       // ⭐ 추가됨
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 45,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.grey),
          ),
        ),
        onPressed: onPressed,    // ⭐ 여기서 실행!
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Image.asset(assetName, height: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}