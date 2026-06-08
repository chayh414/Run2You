// lib/widgets/policy_footer.dart
import 'package:flutter/material.dart';
import '../screens/terms_of_service_screen.dart';
import '../screens/privacy_policy_screen.dart';

class PolicyFooter extends StatelessWidget {
  final double topSpacing;
  final double bottomSpacing;

  const PolicyFooter({
    super.key,
    this.topSpacing = 210,
    this.bottomSpacing = 30,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: topSpacing),

        SizedBox(
          width: double.infinity,
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black45,
              ),
              children: [
                const TextSpan(text: "계속을 클릭하면 당사의 "),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsOfServiceScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      "서비스 이용 약관",
                      style: TextStyle(
                        fontSize: 10,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: " 및 "),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      "개인정보 처리방침",
                      style: TextStyle(
                        fontSize: 10,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: "에\n동의하는 것으로 간주됩니다."),
              ],
            ),
          ),
        ),

        SizedBox(height: bottomSpacing),
      ],
    );
  }
}
