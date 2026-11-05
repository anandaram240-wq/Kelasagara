import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../splash/splash_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  // User ID / email login controllers
  final _loginIdCtrl       = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _obscurePassword = true;

  bool _loading  = false;
  String _error  = '';
  int _tapCount  = 0; // secret dev mode — 5 taps on logo

  void _go(Widget screen) {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));
  }

  // After any auth, re-run splash routing logic to pick correct screen
  void _handleAuthSuccess() {
    _go(const SplashScreen());
  }

  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _error = ''; });
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      _handleAuthSuccess();
    } else {
      final msg = auth.error ?? 'Google Sign-In was cancelled or failed. Please try again.';
      setState(() => _error = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
            action: auth.hasRecoverableError
                ? SnackBarAction(
                    label: 'Retry',
                    textColor: Colors.white,
                    onPressed: () async {
                      setState(() { _loading = true; _error = ''; });
                      final retryOk = await auth.retryProfileLoad();
                      if (!mounted) return;
                      setState(() => _loading = false);
                      if (retryOk) {
                        _handleAuthSuccess();
                      } else {
                        setState(() => _error = auth.error ?? 'Profile retry failed.');
                      }
                    },
                  )
                : null,
          ),
        );
      }
    }
  }

  Future<void> _userIdPasswordLogin() async {
    final rawId   = _loginIdCtrl.text.trim();
    final password = _loginPasswordCtrl.text;
    if (rawId.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your User ID / Email and password');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    final auth = context.read<AuthProvider>();

    bool ok = false;
    if (rawId.contains('@') && !rawId.startsWith('@')) {
      // Direct email login
      ok = await auth.signInWithEmailAndPassword(email: rawId, password: password);
    } else {
      // User ID login — looks up email from Firestore then signs in
      final cleanId = rawId.replaceAll('@', '');
      ok = await auth.signInWithUserIdAndPassword(rawUserId: cleanId, password: password);
    }

    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      Navigator.pop(context); // close modal
      _handleAuthSuccess();
    } else {
      setState(() => _error = auth.error ?? 'Sign in failed');
    }
  }

  void _openUserIdLoginModal() {
    setState(() => _error = '');
    _loginIdCtrl.clear();
    _loginPasswordCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 0, MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('Sign In with User ID', style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead)),
                Text('ಬಳಕೆದಾರ ಐಡಿ / ಇಮೇಲ್ ಮೂಲಕ ಲಾಗಿನ್', style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight)),
                const SizedBox(height: 20),

                if (_error.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.redPale,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppColors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.red, fontWeight: FontWeight.w700))),
                    ]),
                  ),

                Text('User ID or Email / ಬಳಕೆದಾರ ಐಡಿ', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMed)),
                const SizedBox(height: 6),
                TextField(
                  controller: _loginIdCtrl,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  decoration: InputDecoration(
                    hintText: '@ravi_painter or email',
                    prefixIcon: const Icon(Icons.alternate_email, color: AppColors.primary),
                    filled: true, fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  ),
                ),
                const SizedBox(height: 14),

                Text('Password / ಪಾಸ್‌ವರ್ಡ್', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMed)),
                const SizedBox(height: 6),
                StatefulBuilder(builder: (_, setSt) => TextField(
                  controller: _loginPasswordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _userIdPasswordLogin(),
                  style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textLight),
                      onPressed: () => setSt(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true, fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  ),
                )),
                const SizedBox(height: 6),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openForgotPasswordModal();
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Forgot Password? / ಪಾಸ್‌ವರ್ಡ್ ಮರೆತಿರಾ?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _userIdPasswordLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : Text('Sign In →', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openForgotPasswordModal() {
    final resetCtrl = TextEditingController(text: _loginIdCtrl.text.trim());
    String resetError = '';
    bool resetLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 0, MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Reset Password', style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead)),
                Text('ಪಾಸ್‌ವರ್ಡ್ ಮರುಹೊಂದಿಸಿ', style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight)),
                const SizedBox(height: 8),
                Text(
                  'Enter your User ID (@name) or registered Email to receive a password reset link.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textMed),
                ),
                const SizedBox(height: 16),

                if (resetError.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.redPale,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppColors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(resetError, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.red, fontWeight: FontWeight.w700))),
                    ]),
                  ),

                Text('User ID or Email / ಬಳಕೆದಾರ ಐಡಿ ಅಥವಾ ಇಮೇಲ್', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMed)),
                const SizedBox(height: 6),
                TextField(
                  controller: resetCtrl,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  decoration: InputDecoration(
                    hintText: '@ravi_painter or email',
                    prefixIcon: const Icon(Icons.alternate_email, color: AppColors.primary),
                    filled: true, fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: resetLoading ? null : () async {
                      final input = resetCtrl.text.trim();
                      if (input.isEmpty) {
                        setModalState(() => resetError = 'Please enter your User ID or Email');
                        return;
                      }
                      setModalState(() {
                        resetLoading = true;
                        resetError = '';
                      });
                      try {
                        final auth = context.read<AuthProvider>();
                        final sentEmail = await auth.sendPasswordResetForUserIdOrEmail(input);
                        if (!modalCtx.mounted) return;
                        Navigator.pop(modalCtx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                            'Password reset link sent to $sentEmail. Check your email.',
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                          ),
                          backgroundColor: AppColors.green,
                          behavior: SnackBarBehavior.floating,
                        ));
                      } catch (e) {
                        if (!modalCtx.mounted) return;
                        setModalState(() {
                          resetLoading = false;
                          resetError = e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: resetLoading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : Text('Send Reset Link / ಲಿಂಕ್ ಕಳುಹಿಸಿ →', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _loginIdCtrl.dispose();
    _loginPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SingleChildScrollView(
        child: Column(children: [
          // ── Hero Banner ─────────────────────────────────────────────────
          Container(
            height: 340,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFFFC8019), Color(0xFFFF6B35), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
            ),
            child: Stack(children: [
              Positioned(top: -30, right: -30, child: Container(width: 160, height: 160, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle))),
              Positioned(bottom: -20, left: -20, child: Container(width: 120, height: 120, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle))),
              SafeArea(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(height: 16),
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: const Center(child: Text('🏗️', style: TextStyle(fontSize: 44))),
                ).animate().scale(duration: 700.ms, curve: Curves.elasticOut),
                const SizedBox(height: 16),
                Text('ಕೆಲಸಗಾರ', style: GoogleFonts.sora(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)).animate().fadeIn(delay: 300.ms, duration: 500.ms),
                Text('KelasaGaara', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85), letterSpacing: 2)).animate().fadeIn(delay: 400.ms, duration: 400.ms),
                const SizedBox(height: 6),
                Text('Karnataka\'s Job Marketplace', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))).animate().fadeIn(delay: 500.ms),
              ]))),
            ]),
          ),

          Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 16), child: Column(children: [
            Text('Welcome! ನಮಸ್ಕಾರ', style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textHead)).animate().slideY(begin: 0.2, duration: 400.ms, delay: 200.ms).fadeIn(delay: 200.ms),
            const SizedBox(height: 4),
            Text('Sign in to find work or hire workers', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textLight)).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 24),

            // ── Dev mode: 5 taps ───────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _tapCount++),
              child: Text('ಕೆಲಸಗಾರ – Real App', style: GoogleFonts.notoSansKannada(fontSize: 11, color: AppColors.textFaint)),
            ),
            if (_tapCount >= 5) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
                child: Column(children: [
                  Text('⚡ Dev Mode (5-Tap Hidden)', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _tapCount = 0),
                    icon: const Icon(Icons.close, size: 12),
                    label: Text('Hide', style: GoogleFonts.plusJakartaSans(fontSize: 10)),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.textFaint, side: const BorderSide(color: AppColors.border)),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 16),

            // ── Button 1: Google Sign-In ────────────────────────────────
            GestureDetector(
              onTap: _loading ? null : _googleSignIn,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity, height: 54,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                ),
                child: _loading
                    ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('🇬', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Text('Continue with Google', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                      ]),
              ),
            ).animate().slideY(begin: 0.2, duration: 400.ms, delay: 400.ms).fadeIn(delay: 400.ms),

            const SizedBox(height: 14),

            // ── OR divider ──────────────────────────────────────────────
            Row(children: [
              const Expanded(child: Divider()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textFaint, fontWeight: FontWeight.w700))),
              const Expanded(child: Divider()),
            ]),

            const SizedBox(height: 14),

            // ── Button 2: User ID + Password ────────────────────────────
            GestureDetector(
              onTap: _loading ? null : _openUserIdLoginModal,
              child: Container(
                width: double.infinity, height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFFFF6B35)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.alternate_email, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text('Sign in with User ID', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
            ).animate().slideY(begin: 0.2, duration: 400.ms, delay: 500.ms).fadeIn(delay: 500.ms),

            const SizedBox(height: 24),

            Text(
              'New to Kelasagara? Tap Google to register automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('By signing in you agree to our Terms & Privacy Policy', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint)),
            const SizedBox(height: 16),
          ])),
        ]),
      ),
    );
  }
}
