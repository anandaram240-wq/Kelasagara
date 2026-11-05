import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../home/home_shell.dart';

/// Shown after face enrollment succeeds.
/// Listens to Firestore in real-time — auto-navigates the moment admin approves.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});
  @override State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with SingleTickerProviderStateMixin {

  StreamSubscription<DocumentSnapshot>? _sub;
  bool _navigating = false;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _startListener();
  }

  void _startListener() {
    final uid = context.read<AuthProvider>().uid;
    if (uid == null) return;

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || _navigating) return;
      final status = snap.data()?['accountStatus'] ?? '';
      if (status == 'approved' && mounted) {
        _navigating = true;
        // Reload provider state then navigate
        context.read<AuthProvider>().reload().then((_) {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const HomeShell(),
                transitionDuration: const Duration(milliseconds: 600),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
              ),
              (_) => false,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),

              // Animated clock/pending icon
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.08 + _pulseCtrl.value * 0.07),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3 + _pulseCtrl.value * 0.4), width: 3),
                  ),
                  child: const Center(child: Text('⏳', style: TextStyle(fontSize: 52))),
                ),
              ).animate().scale(duration: 600.ms, curve: Curves.elasticOut).fadeIn(),

              const SizedBox(height: 32),

              Text('ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ',
                style: GoogleFonts.notoSansKannada(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textHead))
                  .animate().slideY(begin: 0.2, duration: 400.ms, delay: 200.ms).fadeIn(delay: 200.ms),

              const SizedBox(height: 8),

              Text('Under Review',
                style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textLight))
                  .animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _step('✅', 'Registration Complete', true),
                  _step('✅', 'Face Verification Done', true),
                  _step('⏳', 'Admin Review — In Progress', false, active: true),
                  _step('⬜', 'Account Approved', false),
                ]),
              ).animate().slideY(begin: 0.15, duration: 500.ms, delay: 300.ms).fadeIn(delay: 300.ms),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryPale,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ನಿಮ್ಮ ಮಾಹಿತಿ', style: GoogleFonts.notoSansKannada(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.person_outline, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(auth.name, style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.badge_outlined, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(auth.isHirer ? 'Hirer Account' : 'Worker Account',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textMed, fontWeight: FontWeight.w600)),
                  ]),
                ]),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 20),

              Text(
                'ನಮ್ಮ ತಂಡ ನಿಮ್ಮ ಅರ್ಜಿಯನ್ನು ಪರಿಶೀಲಿಸುತ್ತಿದೆ.\nಅನುಮೋದನೆ ಆದ ತಕ್ಷಣ app ತೆರೆಯುತ್ತದೆ.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight, height: 1.6),
              ).animate().fadeIn(delay: 500.ms),

              const Spacer(),

              // Sign out option
              TextButton.icon(
                onPressed: () => context.read<AuthProvider>().signOut(),
                icon: const Icon(Icons.logout, size: 16, color: AppColors.textFaint),
                label: Text('Sign Out', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(String icon, String label, bool done, {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Text(label, style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          color: done ? AppColors.green : active ? AppColors.primary : AppColors.textFaint,
        )),
        if (active) ...[
          const SizedBox(width: 8),
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.primary,
          )),
        ],
      ]),
    );
  }
}
