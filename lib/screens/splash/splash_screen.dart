import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../auth/welcome_screen.dart';
import '../home/home_shell.dart';
import '../registration/registration_screen.dart';
import 'rejected_screen.dart';
import 'suspended_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Show splash for at least 1.8s for branding
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    final auth = context.read<AuthProvider>();

    // Wait for auth to finish initialising (initial state or loading from auth operation)
    int waited = 0;
    while ((auth.status == AuthStatus.initial || auth.status == AuthStatus.loading) && waited < 5000) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }
    if (!mounted) return;

    _routeByStatus(auth);
  }

  void _routeByStatus(AuthProvider auth) {
    if (!auth.isAuthenticated) {
      _go(const WelcomeScreen());
      return;
    }

    final u = auth.currentUser;
    if (u == null) {
      _go(const WelcomeScreen());
      return;
    }

    // ── Check if user has already registered profile details ─────────────
    final bool hasRegisteredDetails = u.skills.isNotEmpty ||
        u.district.isNotEmpty ||
        u.onboardingComplete ||
        auth.isApproved ||
        auth.accountStatus == AccountStatus.approved ||
        auth.accountStatus == AccountStatus.pendingReview;

    // ── 1. Truly incomplete profile: only brand new unregistered accounts ──
    if (!hasRegisteredDetails &&
        (auth.isPendingProfile || auth.accountStatus == AccountStatus.pendingProfile)) {
      _go(const RegistrationScreen());
      return;
    }

    // ── 2. Hirers do not require face enrollment — direct access to Home ───
    if (auth.isHirer || u.role == 'hirer') {
      _go(const HomeShell());
      return;
    }

    // ── 3. Authenticated Worker: check progression state ───────────────────
    switch (auth.accountStatus) {
      case AccountStatus.pendingProfile:
        // Existing registered worker or new user
        if (hasRegisteredDetails) {
          _go(const HomeShell());
        } else {
          _go(const RegistrationScreen());
        }
        break;

      case AccountStatus.pendingFace:
        // Face authentication is optional during registration. Workers access HomeShell directly.
        _go(const HomeShell());
        break;

      case AccountStatus.pendingReview:
        // Face done, waiting for admin approval or already verified — send to HomeShell
        _go(const HomeShell());
        break;

      case AccountStatus.approved:
        // Full access — role-based dashboard
        _go(const HomeShell());
        break;

      case AccountStatus.rejected:
        _go(const RejectedScreen());
        break;

      case AccountStatus.suspended:
      case AccountStatus.blocked:
        _go(const SuspendedScreen());
        break;

      case AccountStatus.unknown:
        // If they have registered details, let them in
        if (hasRegisteredDetails) {
          _go(const HomeShell());
        } else {
          _go(const RegistrationScreen());
        }
        break;
    }
  }

  void _go(Widget screen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Logo
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30, offset: const Offset(0, 10),
              )],
            ),
            child: const Center(child: Text('🏗️', style: TextStyle(fontSize: 56))),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut).fadeIn(duration: 400.ms),

          const SizedBox(height: 24),

          Text(
            'ಕೆಲಸಗಾರ',
            style: TextStyle(
              fontSize: 36, fontWeight: FontWeight.w900,
              color: Colors.white, letterSpacing: -1,
              shadows: [Shadow(color: Colors.black.withValues(alpha: 0.20), offset: const Offset(0, 2), blurRadius: 8)],
            ),
          ).animate().slideY(begin: 0.3, duration: 500.ms, delay: 300.ms, curve: Curves.easeOutCubic).fadeIn(delay: 300.ms),

          const SizedBox(height: 8),
          Text('KelasaGaara', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85), letterSpacing: 2))
              .animate().fadeIn(delay: 500.ms, duration: 400.ms),

          const SizedBox(height: 6),
          Text("Karnataka's Job Marketplace", style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.70), fontWeight: FontWeight.w500))
              .animate().fadeIn(delay: 700.ms),

          const SizedBox(height: 48),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) =>
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8, height: 8,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), shape: BoxShape.circle),
              ).animate(onPlay: (c) => c.repeat())
                .scale(begin: const Offset(0.6, 0.6), end: const Offset(1.0, 1.0), duration: 600.ms, delay: Duration(milliseconds: i * 200), curve: Curves.easeInOut)
                .then()
                .scale(begin: const Offset(1.0, 1.0), end: const Offset(0.6, 0.6), duration: 600.ms, curve: Curves.easeInOut),
            ),
          ).animate().fadeIn(delay: 900.ms),

          const SizedBox(height: 48),
          Text('VTU Major Project • MCE Hassan',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.50), fontWeight: FontWeight.w500))
              .animate().fadeIn(delay: 1200.ms),
        ]),
      ),
    );
  }
}
