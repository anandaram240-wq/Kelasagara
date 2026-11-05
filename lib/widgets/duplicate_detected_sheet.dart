// lib/widgets/duplicate_detected_sheet.dart
// Privacy-Preserving Duplicate Interception Bottom Sheet (Phase 5).
// Strictly enforces zero PII / no phone / no name / no UID disclosure
// prior to authorized ownership verification.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/auth/welcome_screen.dart';

/// Data from backend duplicate detection response.
class DuplicateDetectionResult {
  final bool isOwnershipVerified;
  final String? recoverySessionId;
  final String? maskedUserId;
  final String? maskedPhone;
  final String? maskedName;
  final int similarityPercent;
  final String message;
  final String? messageKn;

  const DuplicateDetectionResult({
    this.isOwnershipVerified = false,
    this.recoverySessionId,
    this.maskedUserId,
    this.maskedPhone,
    this.maskedName,
    this.similarityPercent = 0,
    required this.message,
    this.messageKn,
  });

  factory DuplicateDetectionResult.fromJson(Map<String, dynamic> json) {
    final verified = json['isOwnershipVerified'] == true;
    return DuplicateDetectionResult(
      isOwnershipVerified: verified,
      recoverySessionId: json['recoverySessionId'] as String?,
      // Prior to ownership proof, candidate identifiers must NOT be populated
      maskedUserId: verified ? (json['maskedUserId'] as String?) : null,
      maskedPhone: verified ? (json['maskedPhone'] as String?) : null,
      maskedName: verified ? (json['maskedName'] as String?) : null,
      similarityPercent: verified ? ((json['similarityPercent'] as num?)?.toInt() ?? 0) : 0,
      message: json['message'] as String? ??
          'A matching facial profile is already registered. If this is your account, please sign in or verify ownership.',
      messageKn: json['messageKn'] as String? ??
          'ಈ ಮುಖದ ಪ್ರೊಫೈಲ್ ಈಗಾಗಲೇ ನೋಂದಾಯಿಸಲ್ಪಟ್ಟಿದೆ. ಇದು ನಿಮ್ಮ ಖಾತೆಯಾಗಿದ್ದರೆ, ದಯವಿಟ್ಟು ಸೈನ್ ಇನ್ ಮಾಡಿ ಅಥವಾ ಮಾಲೀಕತ್ವವನ್ನು ಪರಿಶೀಲಿಸಿ.',
    );
  }
}

/// Bottom sheet shown when duplicate face is detected during enrollment.
class DuplicateDetectedSheet extends StatelessWidget {
  final DuplicateDetectionResult result;
  final VoidCallback? onStartOwnershipVerification;

  const DuplicateDetectedSheet({
    super.key,
    required this.result,
    this.onStartOwnershipVerification,
  });

  static Future<void> show(
    BuildContext context,
    DuplicateDetectionResult result, {
    VoidCallback? onStartOwnershipVerification,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => DuplicateDetectedSheet(
        result: result,
        onStartOwnershipVerification: onStartOwnershipVerification,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVerified = result.isOwnershipVerified;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Security warning banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                const Text('🛡️', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                Text(
                  'ಖಾತೆ ಈಗಾಗಲೇ ನೋಂದಾಯಿಸಲ್ಪಟ್ಟಿದೆ',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFD97706),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Existing Account Detected',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Privacy-Preserving Guidance Card (Zero PII before ownership proof)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.privacy_tip_outlined, size: 20, color: Color(0xFF475569)),
                    const SizedBox(width: 8),
                    Text(
                      'ಗೌಪ್ಯತೆ ಮತ್ತು ಭದ್ರತೆ — Privacy Notice',
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'ಈ ಮುಖದ ಪ್ರೊಫೈಲ್ ನಮ್ಮ ವ್ಯವಸ್ಥೆಯಲ್ಲಿ ಈಗಾಗಲೇ ಅಸ್ತಿತ್ವದಲ್ಲಿದೆ. ಬಳಕೆದಾರರ ಗೌಪ್ಯತೆ ಮತ್ತು ಪ್ಲಾಟ್‌ಫಾರ್ಮ್ ಭದ್ರತೆಯನ್ನು ರಕ್ಷಿಸಲು, ಮಾಲೀಕತ್ವ ದೃಢೀಕರಣಕ್ಕೂ ಮುನ್ನ ಯಾವುದೇ ಖಾತೆಯ ವಿವರಗಳನ್ನು ಬಹಿರಂಗಪಡಿಸಲಾಗುವುದಿಲ್ಲ.\n\n'
                  'A facial profile matching this person is already registered. To preserve privacy and protect accounts from enumeration, details are never disclosed prior to authorized ownership verification.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFF475569),
                    height: 1.5,
                  ),
                ),

                // If authorized ownership was verified via OTP, display verified minimal identifiers
                if (isVerified && result.maskedUserId != null) ...[
                  const Divider(height: 24),
                  Text(
                    'ಪರಿಶೀಲಿಸಿದ ಖಾತೆ — Verified Account Details',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _infoRow('🆔', 'ಬಳಕೆದಾರ ID', result.maskedUserId!),
                  if (result.maskedName != null) _infoRow('👤', 'ಹೆಸರು', result.maskedName!),
                  if (result.maskedPhone != null) _infoRow('📱', 'ಫೋನ್', result.maskedPhone!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Primary Action: Sign In to Existing Account
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.login, size: 18),
              label: Text(
                'ಸೈನ್ ಇನ್ ಮಾಡಿ — Sign In to Existing Account',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Secondary Action: Verify Ownership via Phone OTP
          if (!isVerified)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (onStartOwnershipVerification != null) {
                    onStartOwnershipVerification!();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    );
                  }
                },
                icon: const Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF4338CA)),
                label: Text(
                  'ಮಾಲೀಕತ್ವ ಪರಿಶೀಲನೆ — Verify Ownership via OTP',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: const Color(0xFF4338CA),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF4338CA), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),

          // Dismiss action
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'ರದ್ದುಮಾಡಿ — Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _infoRow(String emoji, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: const Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
