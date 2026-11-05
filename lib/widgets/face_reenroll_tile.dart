// lib/widgets/face_reenroll_tile.dart
// Re-enroll face option for users who already have a face template.
// Allows updating face template (glasses, weight change, haircut).
// Runs fresh 1:N dedup before writing new template. DPDPA §8(3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/face_enrollment_screen.dart';

class FaceReEnrollTile extends StatelessWidget {
  const FaceReEnrollTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // Only show if user already has a face template enrolled
        if (!auth.hasFaceTemplate) return const SizedBox.shrink();

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.04),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
            children: [
              _tile(
                context,
                icon: Icons.face_retouching_natural,
                iconColor: const Color(0xFF7C3AED),
                title: 'ಮುಖ ಮರು-ನೋಂದಣಿ',
                subtitle: 'Re-enroll Face ID (glasses / haircut / weight change)',
                onTap: () => _startReEnroll(context),
              ),
              const Divider(height: 1, indent: 60),
              _tile(
                context,
                icon: Icons.security_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'ಮುಖ ಪರಿಶೀಲನೆ ಸ್ಥಿತಿ',
                subtitle: 'Face verification: Active ✅',
                onTap: null,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'ISO 30107-3',
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.sora(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1E293B),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          color: const Color(0xFF64748B),
        ),
      ),
      trailing: trailing ?? (onTap != null
          ? const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1), size: 20)
          : null),
    );
  }

  Future<void> _startReEnroll(BuildContext context) async {
    HapticFeedback.mediumImpact();
    // Navigate directly to FaceEnrollmentScreen in re-enrollment mode.
    // Live camera preview starts immediately without intermediary modals.
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const FaceEnrollmentScreen(isReEnrollment: true),
      ),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ ಮುಖ ಮರು-ನೋಂದಣಿ ಯಶಸ್ವಿಯಾಗಿದೆ / Face ID updated successfully!',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
