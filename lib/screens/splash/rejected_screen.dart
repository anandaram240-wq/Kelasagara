import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

class RejectedScreen extends StatelessWidget {
  const RejectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reason = auth.currentUser?.rejectionReason ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('❌', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 24),
            Text('Application Rejected',
              style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.red)),
            Text('ಅರ್ಜಿ ತಿರಸ್ಕರಿಸಲಾಗಿದೆ',
              style: GoogleFonts.notoSansKannada(fontSize: 14, color: AppColors.textLight)),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.red.withValues(alpha: 0.3))),
                child: Text(reason, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.red)),
              ),
            ],
            const SizedBox(height: 32),
            Text('ಹೆಚ್ಚಿನ ಮಾಹಿತಿಗೆ support@kelasagara.in ಸಂಪರ್ಕಿಸಿ.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => auth.signOut(),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
            ),
          ]),
        ),
      ),
    );
  }
}
