// lib/services/auth/password_policy_service.dart
// Password Policy, Strength Evaluation & Criteria Validator (Change 2)

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum PasswordStrengthLevel {
  none,
  weak,
  fair,
  good,
  strong;

  String get label => switch (this) {
    none   => 'Enter Password',
    weak   => 'Weak',
    fair   => 'Fair',
    good   => 'Good',
    strong => 'Strong',
  };

  String get labelKn => switch (this) {
    none   => 'ಪಾಸ್‌ವರ್ಡ್ ನಮೂದಿಸಿ',
    weak   => 'ದುರ್ಬಲ',
    fair   => 'ಪರವಾಗಿಲ್ಲ',
    good   => 'ಉತ್ತಮ',
    strong => 'ಬಲವಾದ',
  };

  Color get color => switch (this) {
    none   => AppColors.textFaint,
    weak   => AppColors.red,
    fair   => const Color(0xFFF59E0B), // Amber
    good   => const Color(0xFF0284C7), // Blue
    strong => AppColors.green,
  };

  double get fraction => switch (this) {
    none   => 0.0,
    weak   => 0.25,
    fair   => 0.50,
    good   => 0.75,
    strong => 1.0,
  };
}

class PasswordRuleCheck {
  final String label;
  final String labelKn;
  final bool isMet;

  const PasswordRuleCheck({
    required this.label,
    required this.labelKn,
    required this.isMet,
  });
}

class PasswordStrengthResult {
  final PasswordStrengthLevel level;
  final int score; // 0 to 4
  final List<PasswordRuleCheck> rules;
  final String? feedback;

  const PasswordStrengthResult({
    required this.level,
    required this.score,
    required this.rules,
    this.feedback,
  });

  bool get isAcceptable => score >= 2 && rules.first.isMet; // at least 8 chars + fair/good/strong
}

class PasswordPolicyService {
  static PasswordStrengthResult evaluate(
    String password, {
    String? userId,
    String? displayName,
  }) {
    if (password.isEmpty) {
      return const PasswordStrengthResult(
        level: PasswordStrengthLevel.none,
        score: 0,
        rules: [
          PasswordRuleCheck(label: 'At least 8 characters', labelKn: 'ಕನಿಷ್ಠ 8 ಅಕ್ಷರಗಳು', isMet: false),
          PasswordRuleCheck(label: 'Contains lowercase & uppercase', labelKn: 'ದೊಡ್ಡ ಮತ್ತು ಸಣ್ಣ ಅಕ್ಷರಗಳು', isMet: false),
          PasswordRuleCheck(label: 'Contains at least 1 number', labelKn: 'ಕನಿಷ್ಠ 1 ಸಂಖ್ಯೆ', isMet: false),
          PasswordRuleCheck(label: 'Contains a symbol (!@#\$%^&*)', labelKn: 'ಕನಿಷ್ಠ 1 ಚಿಹ್ನೆ', isMet: false),
        ],
      );
    }

    final hasMinLength = password.length >= 8;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial = RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(password);

    final rules = [
      PasswordRuleCheck(label: 'At least 8 characters', labelKn: 'ಕನಿಷ್ಠ 8 ಅಕ್ಷರಗಳು', isMet: hasMinLength),
      PasswordRuleCheck(label: 'Contains lowercase & uppercase', labelKn: 'ದೊಡ್ಡ ಮತ್ತು ಸಣ್ಣ ಅಕ್ಷರಗಳು', isMet: hasUpper && hasLower),
      PasswordRuleCheck(label: 'Contains at least 1 number', labelKn: 'ಕನಿಷ್ಠ 1 ಸಂಖ್ಯೆ', isMet: hasDigit),
      PasswordRuleCheck(label: 'Contains a symbol (!@#\$%^&*)', labelKn: 'ಕನಿಷ್ಠ 1 ಚಿಹ್ನೆ', isMet: hasSpecial),
    ];

    int score = 0;
    if (hasMinLength) score++;
    if (hasUpper && hasLower) score++;
    if (hasDigit) score++;
    if (hasSpecial) score++;

    // Extra length bonus
    if (password.length >= 12 && score >= 3) {
      score = 4;
    }

    // Check if password dangerously contains username
    String? feedback;
    if (userId != null && userId.trim().length >= 3) {
      if (password.toLowerCase().contains(userId.trim().toLowerCase())) {
        score = (score > 1) ? 1 : score;
        feedback = 'Password should not contain your User ID';
      }
    }

    final level = switch (score) {
      0 => PasswordStrengthLevel.none,
      1 => PasswordStrengthLevel.weak,
      2 => PasswordStrengthLevel.fair,
      3 => PasswordStrengthLevel.good,
      _ => PasswordStrengthLevel.strong,
    };

    return PasswordStrengthResult(
      level: level,
      score: score,
      rules: rules,
      feedback: feedback,
    );
  }
}
