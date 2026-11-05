import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/jobs_provider.dart';
import '../../services/journey_service.dart';
import '../../services/navigation_engine.dart';
import '../admin/admin_dashboard.dart';
import '../auth/welcome_screen.dart';
import 'worker_dashboard.dart';
import 'hirer_dashboard.dart';
import '../applications/applications_screen.dart';
import '../assessment/skill_passport_screen.dart';
import '../voice/voice_command_center_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/update_dialog.dart';

// Safe sign-out: stops GPS/navigation first, clears auth state, and redirects to WelcomeScreen
Future<void> _safeSignOut(BuildContext context, AuthProvider auth) async {
  // Stop any active journey — non-blocking from UI perspective
  JourneyService.instance.stopTracking();
  NavigationEngine.instance.stop();
  await auth.signOut();
  if (context.mounted) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }
}


class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _init() {
    final auth = context.read<AuthProvider>();
    final jobs = context.read<JobsProvider>();
    // Start real-time job stream
    jobs.startListening();
    if (auth.isHirer && auth.uid != null) {
      jobs.startHirerStream(auth.uid!);
    }
    // Load applied jobs for worker
    if (auth.isWorker && auth.uid != null) {
      jobs.loadAppliedJobs(auth.uid!);
    }
    // Check for app updates — 2 second delay so UI renders first
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) UpdateDialog.checkAndShow(context);
    });
  }

  @override
  void dispose() {
    // Stop listening when leaving HomeShell (e.g. sign out)
    // Jobs provider itself handles cleanup in its dispose()
    super.dispose();
  }


  void _switchTab(int tab) {
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // ── Unauthenticated: redirect immediately to WelcomeScreen ─────────────
    if (!auth.isAuthenticated || auth.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (_) => false,
          );
        }
      });
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final isHirer = auth.isHirer;

    // ── Admin: full-screen admin dashboard ────────────────────────────────
    if (auth.isAdmin) {
      return const AdminDashboard();
    }

    // ── Approval guard ────────────────────────────────────────────────────
    // Auto-approve users who have completed face verification
    // (admin reviews only for suspicious accounts — not blocking all new users)
    final canEnter = auth.isApproved || auth.isAdmin || isHirer || (auth.isWorker && auth.faceVerified);

    if (!canEnter) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('⏳', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text('Account Pending Approval', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textHead)),
            const SizedBox(height: 8),
            Text('Your account is under review. This page will update automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textLight)),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: () => _safeSignOut(context, auth), child: const Text('Sign Out')),
          ]),
        )),
      );
    }

    // ── Role-based tabs ───────────────────────────────────────────────────
    final tabs = isHirer
      ? [const HirerDashboard(), const ApplicationsScreen(), VoiceCommandCenterScreen(onNavigate: _switchTab), const ProfileScreen()]
      : [WorkerDashboard(onVoiceNavigate: _switchTab), const ApplicationsScreen(), const SkillPassportScreen(), const ProfileScreen()];

    final hirerLabels = [('🏢', 'Jobs'), ('📋', 'Applicants'), ('🎙️', 'Voice AI'), ('👤', 'Profile')];
    final workerLabels = [('🏗️', 'Find Work'), ('📋', 'My Apps'), ('🎯', 'Passport'), ('👤', 'Profile')];
    final labels = isHirer ? hirerLabels : workerLabels;

    return Scaffold(
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: const Border(top: BorderSide(color: AppColors.divider)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: List.generate(labels.length, (i) {
              final active = _tab == i;
              final isVoice = i == 2;
              return Expanded(child: GestureDetector(
                onTap: () => _switchTab(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(vertical: isVoice ? 10 : 8, horizontal: 4),
                  decoration: isVoice ? BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF7C3AED), AppColors.primary]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ) : BoxDecoration(
                    color: active ? AppColors.primaryPale : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Voice AI tab gets shimmer animation to draw attention
                    if (isVoice)
                      Text(labels[i].$1, style: const TextStyle(fontSize: 22))
                          .animate(onPlay: (c) => c.repeat())
                          .shimmer(duration: 2500.ms, color: Colors.white.withValues(alpha: 0.5))
                    else
                      Text(labels[i].$1, style: const TextStyle(fontSize: 22))
                          .animate(target: active ? 1 : 0)
                          .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.05, 1.05), duration: 200.ms),
                    const SizedBox(height: 3),
                    Text(
                      labels[i].$2,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isVoice ? Colors.white : active ? AppColors.primary : AppColors.textFaint,
                      ),
                    ),
                    // Active indicator line under label
                    if (active && !isVoice) ...[
                      const SizedBox(height: 3),
                      Container(
                        width: 20, height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ]),
                ),
              ));
            })),
          ),
        ),
      ),
    );
  }
}
