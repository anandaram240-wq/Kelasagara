// lib/screens/registration/registration_screen.dart
// World-Class Account Registration, Unique User ID & Profile Setup
// Full support for Direct Registration and Post-Auth Onboarding Resumption
// Supports both Worker and Hirer progressive multi-step onboarding journeys.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../core/constants/karnataka_locations.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_id_service.dart';
import '../../services/auth/password_policy_service.dart';
import '../../services/profile_media_service.dart';
import '../auth/face_enrollment_screen.dart';
import '../home/home_shell.dart';

enum UserIdStatus { empty, checking, available, taken, invalid, reserved, networkError }

class RegistrationScreen extends StatefulWidget {
  final bool isDirectRegistration; // true if registering from WelcomeScreen without prior auth

  const RegistrationScreen({
    super.key,
    this.isDirectRegistration = false,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _pageCtrl = PageController();
  int _page = 0;
  bool _saving = false;
  String _globalError = '';

  // Form Controllers
  final _nameCtrl = TextEditingController();
  final _userIdCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _villageCtrl = TextEditingController();

  // Password UI
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  PasswordStrengthResult _strengthResult = const PasswordStrengthResult(
    level: PasswordStrengthLevel.none,
    score: 0,
    rules: [],
  );

  // User ID Validation & Suggestion State
  UserIdStatus _userIdStatus = UserIdStatus.empty;
  String _userIdFeedback = '';
  List<String> _userIdSuggestions = [];
  Timer? _debounceTimer;

  // Role & Profile State
  String _role = 'worker'; // 'worker' | 'hirer'
  String _district = '';
  String _taluk = '';
  String _primarySkill = 'mason';
  final Set<String> _secondarySkills = {};
  double _dailyRate = 700;
  int _experienceYears = 3;
  String _experienceLevel = '3-5 yrs';
  int _serviceRadiusKm = 15;
  bool _isAvailable = true;

  // Avatar Photo State
  File? _avatarFile;
  String _avatarUrl = '';

  // Successful Registration State
  bool _registrationComplete = false;
  String _confirmedUserId = '';
  String _confirmedDisplayName = '';

  late final UserIdService _userIdService;

  @override
  void initState() {
    super.initState();
    _userIdService = UserIdService();

    // Pre-fill existing user info if authenticated (e.g. from Google Sign-In)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        final u = auth.currentUser!;
        if (u.displayName.isNotEmpty) _nameCtrl.text = u.displayName;
        if (u.email.isNotEmpty) _emailCtrl.text = u.email;
        if (u.phone.isNotEmpty) _phoneCtrl.text = u.phone;
        if (u.userId.isNotEmpty) {
          _userIdCtrl.text = u.userId;
          _checkUserIdAvailability(u.userId);
        }
        if (u.district.isNotEmpty) _district = u.district;
        if (u.taluk.isNotEmpty) _taluk = u.taluk;
        if (u.village.isNotEmpty) _villageCtrl.text = u.village;
        if (u.bio.isNotEmpty) _bioCtrl.text = u.bio;
        if (u.photoUrl.isNotEmpty) _avatarUrl = u.photoUrl;
        if (u.skills.isNotEmpty) {
          _primarySkill = u.skills.first;
          _secondarySkills.addAll(u.skills.skip(1));
        }
        if (u.dailyRate > 0) _dailyRate = u.dailyRate.toDouble();
        if (u.experienceYears > 0) _experienceYears = u.experienceYears;
        if (u.experienceLevel.isNotEmpty) _experienceLevel = u.experienceLevel;
        if (u.serviceRadiusKm > 0) _serviceRadiusKm = u.serviceRadiusKm;
        if (u.role.isNotEmpty) _role = u.role;
        setState(() {});
      }
    });

    _userIdCtrl.addListener(_onUserIdChanged);
    _passwordCtrl.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _userIdCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _bioCtrl.dispose();
    _villageCtrl.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    setState(() {
      _strengthResult = PasswordPolicyService.evaluate(
        _passwordCtrl.text,
        userId: _userIdCtrl.text,
        displayName: _nameCtrl.text,
      );
    });
  }

  void _onUserIdChanged() {
    _debounceTimer?.cancel();
    final text = _userIdCtrl.text.trim();

    if (text.isEmpty) {
      setState(() {
        _userIdStatus = UserIdStatus.empty;
        _userIdFeedback = '';
        _userIdSuggestions = [];
      });
      return;
    }

    final val = UserIdService.validate(text);
    if (!val.isValid) {
      setState(() {
        _userIdStatus = UserIdStatus.invalid;
        _userIdFeedback = val.errorMessage ?? 'Invalid format';
        _userIdSuggestions = [];
      });
      return;
    }

    setState(() {
      _userIdStatus = UserIdStatus.checking;
      _userIdFeedback = 'Checking availability...';
      _userIdSuggestions = [];
    });

    // 400ms debounce
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _checkUserIdAvailability(text);
    });
  }

  Future<void> _checkUserIdAvailability(String rawId) async {
    final val = UserIdService.validate(rawId);
    if (val.isValid && UserIdService.reservedUserIds.contains(UserIdService.normalize(rawId))) {
      if (!mounted) return;
      setState(() {
        _userIdStatus = UserIdStatus.reserved;
        _userIdFeedback = '@${UserIdService.normalize(rawId)} is a reserved name';
        _userIdSuggestions = [];
      });
      return;
    }

    try {
      final available = await _userIdService.checkUserIdAvailability(rawId);
      if (!mounted) return;

      if (available) {
        setState(() {
          _userIdStatus = UserIdStatus.available;
          _userIdFeedback = '@${UserIdService.normalize(rawId)} is available! ✓';
          _userIdSuggestions = [];
        });
      } else {
        final suggestions = await _userIdService.generateAvailableSuggestions(rawId, maxCount: 3);
        if (!mounted) return;

        setState(() {
          _userIdStatus = UserIdStatus.taken;
          _userIdFeedback = '@${UserIdService.normalize(rawId)} is already taken';
          _userIdSuggestions = suggestions;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userIdStatus = UserIdStatus.networkError;
        _userIdFeedback = 'Could not check availability. Check network and retry.';
        _userIdSuggestions = [];
      });
    }
  }

  void _applySuggestion(String suggestion) {
    _userIdCtrl.text = suggestion;
    _userIdCtrl.selection = TextSelection.fromPosition(TextPosition(offset: suggestion.length));
    _checkUserIdAvailability(suggestion);
  }

  // Dynamic Multi-Step Pages:
  // For Worker: ['Role', 'Identity', 'Skills', 'Experience', 'Service Area', 'Review']
  // For Hirer:  ['Role', 'Identity', 'Location', 'Review']
  List<String> get _pages {
    if (_role == 'worker') {
      return ['Role', 'Identity', 'Skills', 'Experience', 'Service Area', 'Review'];
    } else {
      return ['Role', 'Identity', 'Location', 'Review'];
    }
  }

  void _goToPage(int targetPage) {
    if (targetPage < 0 || targetPage >= _pages.length) return;
    setState(() => _page = targetPage);
    _pageCtrl.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _next() async {
    setState(() => _globalError = '');
    final currentPages = _pages;
    final stepName = currentPages[_page];

    if (stepName == 'Identity') {
      if (_nameCtrl.text.trim().isEmpty) {
        _showToast('Please enter your full name');
        return;
      }
      if (widget.isDirectRegistration && _emailCtrl.text.trim().isEmpty) {
        _showToast('Please enter your email');
        return;
      }
      if (_userIdCtrl.text.trim().isEmpty) {
        _showToast('Please choose a User ID');
        return;
      }
      if (_userIdStatus == UserIdStatus.invalid) {
        _showToast(_userIdFeedback.isNotEmpty ? _userIdFeedback : 'Invalid User ID format');
        return;
      }
      if (_userIdStatus == UserIdStatus.taken) {
        _showToast('User ID is already taken. Please choose another.');
        return;
      }
      if (_userIdStatus == UserIdStatus.reserved) {
        _showToast('This User ID is reserved. Please choose another.');
        return;
      }
      if (_userIdStatus == UserIdStatus.networkError) {
        _showToast('Could not verify User ID. Please check your network and try again.');
        return;
      }
      if (_userIdStatus == UserIdStatus.checking) {
        _showToast('Checking User ID availability, please wait...');
        return;
      }
      if (_phoneCtrl.text.trim().length != 10) {
        _showToast('Please enter a valid 10-digit mobile number');
        return;
      }
      if (_passwordCtrl.text.isEmpty) {
        _showToast('Please set a password / ಪಾಸ್‌ವರ್ಡ್ ಹೊಂದಿಸಿ');
        return;
      }
      if (_passwordCtrl.text.length < 8) {
        _showToast('Password must be at least 8 characters');
        return;
      }
      if (!_strengthResult.isAcceptable) {
        _showToast('Please choose a stronger password (at least 8 chars + numbers/symbols)');
        return;
      }
      if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
        _showToast('Passwords do not match / ಪಾಸ್‌ವರ್ಡ್‌ಗಳು ಹೊಂದಿಕೆಯಾಗುತ್ತಿಲ್ಲ');
        return;
      }
    } else if (stepName == 'Skills') {
      if (_primarySkill.isEmpty) {
        _showToast('Please select your primary skill');
        return;
      }
    } else if (stepName == 'Experience') {
      if (_experienceLevel.isEmpty) {
        _showToast('Please select your experience level');
        return;
      }
    } else if (stepName == 'Service Area' || stepName == 'Location') {
      if (_district.isEmpty) {
        _showToast('Please select your District');
        return;
      }
    }

    if (_page < currentPages.length - 1) {
      _goToPage(_page + 1);
    } else {
      _submitRegistration();
    }
  }

  void _back() {
    if (_page > 0) {
      _goToPage(_page - 1);
    } else {
      Navigator.maybePop(context);
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _pickAvatar() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Profile Photo',
              style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textHead),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primaryPale,
                child: Icon(Icons.photo_camera, color: AppColors.primary),
              ),
              title: Text('Take Photo', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              onTap: () async {
                Navigator.pop(ctx);
                final file = await ProfileMediaService.instance.pickImage(source: ImageSource.camera);
                if (file != null && mounted) {
                  setState(() => _avatarFile = file);
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primaryPale,
                child: Icon(Icons.photo_library, color: AppColors.primary),
              ),
              title: Text('Choose from Gallery', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              onTap: () async {
                Navigator.pop(ctx);
                final file = await ProfileMediaService.instance.pickImage(source: ImageSource.gallery);
                if (file != null && mounted) {
                  setState(() => _avatarFile = file);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRegistration() async {
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();

    try {
      String uploadedPhotoUrl = '';
      if (_avatarFile != null && auth.uid != null) {
        final uploadRes = await ProfileMediaService.instance.uploadAvatarPhoto(
          uid: auth.uid!,
          imageFile: _avatarFile!,
        );
        if (uploadRes.success && uploadRes.downloadUrl != null) {
          uploadedPhotoUrl = uploadRes.downloadUrl!;
        }
      }

      final allSkills = [
        if (_primarySkill.isNotEmpty) _primarySkill,
        ..._secondarySkills.where((s) => s != _primarySkill),
      ];

      if (widget.isDirectRegistration) {
        final ok = await auth.registerWithCredentials(
          rawUserId: _userIdCtrl.text.trim(),
          password: _passwordCtrl.text,
          displayName: _nameCtrl.text.trim(),
          role: _role,
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          district: _district,
          taluk: _taluk,
          village: _villageCtrl.text.trim(),
          skills: allSkills,
          dailyRate: _dailyRate.toInt(),
          experienceYears: _experienceYears,
          experienceLevel: _experienceLevel,
          serviceRadiusKm: _serviceRadiusKm,
          bio: _bioCtrl.text.trim(),
          photoUrl: uploadedPhotoUrl.isNotEmpty ? uploadedPhotoUrl : _avatarUrl,
        );

        if (!ok) {
          throw Exception(auth.error ?? 'Registration failed. Please try again.');
        }

        // Post-registration avatar upload if image was selected before uid existed
        if (_avatarFile != null && uploadedPhotoUrl.isEmpty && auth.uid != null) {
          final uploadRes = await ProfileMediaService.instance.uploadAvatarPhoto(
            uid: auth.uid!,
            imageFile: _avatarFile!,
          );
          if (uploadRes.success && uploadRes.downloadUrl != null) {
            await auth.updateProfile(
              name: _nameCtrl.text.trim(),
              role: _role,
              district: _district,
              taluk: _taluk,
              village: _villageCtrl.text.trim(),
              skills: allSkills,
              dailyRate: _dailyRate.toInt(),
              experienceYears: _experienceYears,
              experienceLevel: _experienceLevel,
              serviceRadiusKm: _serviceRadiusKm,
              photoUrl: uploadRes.downloadUrl,
              bio: _bioCtrl.text.trim(),
            );
          }
        }
      } else {
        // Post-Auth Onboarding (Google Sign-In)
        await auth.updateProfile(
          name: _nameCtrl.text.trim(),
          role: _role,
          district: _district,
          taluk: _taluk,
          village: _villageCtrl.text.trim(),
          skills: allSkills,
          dailyRate: _dailyRate.toInt(),
          experienceYears: _experienceYears,
          experienceLevel: _experienceLevel,
          serviceRadiusKm: _serviceRadiusKm,
          userId: _userIdCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          bio: _bioCtrl.text.trim(),
          photoUrl: uploadedPhotoUrl.isNotEmpty ? uploadedPhotoUrl : (_avatarUrl.isNotEmpty ? _avatarUrl : null),
        );
        if (_passwordCtrl.text.isNotEmpty) {
          await auth.setPasswordForCurrentUser(_passwordCtrl.text);
        }
      }

      if (!mounted) return;
      setState(() {
        _saving = false;
        _registrationComplete = true;
        _confirmedUserId = _userIdCtrl.text.trim();
        _confirmedDisplayName = _nameCtrl.text.trim();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _globalError = e.toString().replaceAll('Exception: ', '');
      });
      _showToast(_globalError);
    }
  }

  void _onFinish() {
    // V19 Journey A: Both worker and hirer registrations require secure face enrollment
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const FaceEnrollmentScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_registrationComplete) {
      return _buildConfirmationScreen();
    }

    final totalPages = _pages.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top App Bar & Progress Indicator ─────────────────────────────
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 14, 20, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.textHead),
                        onPressed: _back,
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Step ${_page + 1} of $totalPages • ${_pages[_page]}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textLight,
                              ),
                            ),
                            Text(
                              _stepHeaderTitle(),
                              style: GoogleFonts.sora(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textHead,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        height: 42,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: (_page + 1) / totalPages,
                              backgroundColor: AppColors.divider,
                              color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                              strokeWidth: 3.5,
                            ),
                            Text(
                              '${((_page + 1) / totalPages * 100).toInt()}%',
                              style: GoogleFonts.sora(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_page + 1) / totalPages,
                      backgroundColor: AppColors.divider,
                      color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),

            if (_globalError.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.redPale,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _globalError,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Multi-Step Pages ─────────────────────────────────────────────
            Expanded(
              child: PageView(
                key: ValueKey(_role),
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: _role == 'worker'
                    ? [
                        _rolePage(),
                        _identityPage(),
                        _skillsPage(),
                        _experiencePage(),
                        _serviceAreaPage(),
                        _reviewPage(),
                      ]
                    : [
                        _rolePage(),
                        _identityPage(),
                        _hirerLocationPage(),
                        _reviewPage(),
                      ],
              ),
            ),

            // ── Bottom Action Bar ────────────────────────────────────────────
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _saving ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _bottomButtonLabel(),
                              style: GoogleFonts.sora(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stepHeaderTitle() {
    final step = _pages[_page];
    return switch (step) {
      'Role' => 'Choose Role',
      'Identity' => 'Account Identity',
      'Skills' => 'Skills & Daily Rate',
      'Experience' => 'Trade Experience',
      'Service Area' => 'Service Area',
      'Location' => 'Hiring Location',
      'Review' => 'Review & Confirm',
      _ => 'Account Setup',
    };
  }

  String _bottomButtonLabel() {
    if (_page == 0) {
      return _role == 'worker' ? 'Continue as Worker →' : 'Continue as Hirer →';
    }
    if (_page == _pages.length - 1) {
      return 'Submit Profile & Verify Face →';
    }
    return 'Continue →';
  }

  // ── Step 0: Role Selection (Section 4) ──────────────────────────────────
  Widget _rolePage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose Your Path',
              style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 4),
            Text(
              'ನಿಮ್ಮ ಪಾತ್ರವನ್ನು ಆಯ್ಕೆಮಾಡಿ — Are you looking for work or hiring workers?',
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 24),

            // Worker Card
            GestureDetector(
              onTap: () {
                setState(() => _role = 'worker');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _role == 'worker' ? AppColors.primaryPale : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _role == 'worker' ? AppColors.primary : AppColors.border,
                    width: _role == 'worker' ? 2.5 : 1.5,
                  ),
                  boxShadow: [
                    if (_role == 'worker')
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(child: Text('👷', style: TextStyle(fontSize: 28))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Worker',
                                    style: GoogleFonts.sora(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textHead,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'ಕಾರ್ಮಿಕ',
                                      style: GoogleFonts.notoSansKannada(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'I want to work / ನಾನು ಕೆಲಸ ಹುಡುಕುತ್ತಿದ್ದೇನೆ',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _role == 'worker' ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: _role == 'worker' ? AppColors.primary : AppColors.textFaint,
                          size: 26,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    _roleBullet(Icons.payments_outlined, 'Set your own daily wage & service radius'),
                    _roleBullet(Icons.near_me_outlined, 'Get booked directly by nearby verified hirers'),
                    _roleBullet(Icons.verified_outlined, 'Build verified work history & authentic reputation'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Hirer Card
            GestureDetector(
              onTap: () {
                setState(() => _role = 'hirer');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _role == 'hirer' ? const Color(0xFFF3E8FF) : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.border,
                    width: _role == 'hirer' ? 2.5 : 1.5,
                  ),
                  boxShadow: [
                    if (_role == 'hirer')
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(child: Text('🏢', style: TextStyle(fontSize: 28))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Hirer',
                                    style: GoogleFonts.sora(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textHead,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'ನೇಮಕದಾರ',
                                      style: GoogleFonts.notoSansKannada(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'I want to hire / ನಾನು ಕೆಲಸಗಾರರನ್ನು ನೇಮಿಸುತ್ತೇನೆ',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _role == 'hirer' ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.textFaint,
                          size: 26,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    _roleBullet(Icons.search, 'Discover verified workers in your district with road ETA'),
                    _roleBullet(Icons.flash_on_outlined, 'Instant direct booking with 6-digit OTP security'),
                    _roleBullet(Icons.chat_bubble_outline, 'Direct chat and transparent job coordination'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _roleBullet(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textLight),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textBody,
                ),
              ),
            ),
          ],
        ),
      );

  // ── Step 1: Account Identity (Section 5) ──────────────────────────────────
  Widget _identityPage() {
    final auth = context.watch<AuthProvider>();
    final googleEmail = auth.currentUser?.email ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Information',
            style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textHead),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your unique @username and contact details.',
            style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
          ),
          const SizedBox(height: 24),

          // Profile Avatar Picker
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface2,
                      border: Border.all(color: AppColors.border, width: 2),
                    ),
                    child: ClipOval(
                      child: _avatarFile != null
                          ? Image.file(_avatarFile!, width: 90, height: 90, fit: BoxFit.cover)
                          : _avatarUrl.isNotEmpty
                              ? Image.network(
                                  _avatarUrl,
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.person, size: 44, color: AppColors.textLight),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.person, size: 44, color: AppColors.textLight),
                                ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _avatarFile != null || _avatarUrl.isNotEmpty ? 'Tap to change photo' : 'Add Profile Photo (Optional)',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),

          _inputLabel(_role == 'worker' ? 'Full Name / ಪೂರ್ಣ ಹೆಸರು *' : 'Full Name or Business Name *'),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
            decoration: _inputDecoration(
              hint: _role == 'worker' ? 'e.g. Ravi Kumar / ರವಿ ಕುಮಾರ್' : 'e.g. Ramesh Enterprises',
              prefixIcon: const Icon(Icons.person_outline, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),

          _inputLabel('Kelasagara User ID *'),
          TextField(
            controller: _userIdCtrl,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.text,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
              LengthLimitingTextInputFormatter(20),
            ],
            style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textHead),
            decoration: _inputDecoration(
              prefixText: '@',
              hint: _role == 'worker' ? 'ravi_painter' : 'ramesh_builds',
              prefixIcon: const Icon(Icons.alternate_email, color: AppColors.primary),
              suffixIcon: _buildUserIdSuffixIcon(),
            ),
          ),
          const SizedBox(height: 8),

          // Live status feedback
          if (_userIdFeedback.isNotEmpty)
            Row(
              children: [
                Icon(
                  _userIdStatus == UserIdStatus.available
                      ? Icons.check_circle
                      : _userIdStatus == UserIdStatus.taken
                          ? Icons.cancel
                          : _userIdStatus == UserIdStatus.networkError
                              ? Icons.wifi_off
                              : _userIdStatus == UserIdStatus.reserved
                                  ? Icons.block
                                  : Icons.info_outline,
                  size: 15,
                  color: _userIdStatus == UserIdStatus.available
                      ? AppColors.green
                      : _userIdStatus == UserIdStatus.taken
                          ? AppColors.red
                          : _userIdStatus == UserIdStatus.networkError
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _userIdFeedback,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _userIdStatus == UserIdStatus.available
                          ? AppColors.green
                          : _userIdStatus == UserIdStatus.taken
                              ? AppColors.red
                              : _userIdStatus == UserIdStatus.networkError
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),

          // Suggestion chips when taken
          if (_userIdSuggestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Available Suggestions (ಲಭ್ಯವಿರುವ ಸಲಹೆಗಳು):',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _userIdSuggestions.map((sug) => ActionChip(
                avatar: const Icon(Icons.add, size: 14, color: AppColors.primary),
                label: Text('@$sug', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                backgroundColor: AppColors.primaryPale,
                side: const BorderSide(color: AppColors.primaryBorder),
                onPressed: () => _applySuggestion(sug),
              )).toList(),
            ),
          ],
          const SizedBox(height: 16),

          // ── Password Creation (Both Direct and Google Accounts) ─────
          _inputLabel('Set Password / ಪಾಸ್‌ವರ್ಡ್ ಹೊಂದಿಸಿ *'),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
            decoration: _inputDecoration(
              hint: '••••••••',
              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textLight),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Password Strength Meter Bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _strengthResult.level.fraction,
                    backgroundColor: AppColors.divider,
                    color: _strengthResult.level.color,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_strengthResult.level.label} (${_strengthResult.level.labelKn})',
                style: GoogleFonts.sora(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _strengthResult.level.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Password Rules Checklist
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _strengthResult.rules.map((r) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: r.isMet ? AppColors.greenPale : AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: r.isMet ? AppColors.green : AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(r.isMet ? Icons.check : Icons.circle_outlined, size: 12, color: r.isMet ? AppColors.green : AppColors.textLight),
                  const SizedBox(width: 6),
                  Text(
                    r.label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: r.isMet ? AppColors.green : AppColors.textLight,
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),

          if (_strengthResult.feedback != null) ...[
            const SizedBox(height: 8),
            Text(
              '⚠️ ${_strengthResult.feedback}',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.red),
            ),
          ],

          const SizedBox(height: 16),
          _inputLabel('Confirm Password / ಪಾಸ್‌ವರ್ಡ್ ಖಚಿತಪಡಿಸಿ *'),
          TextField(
            controller: _confirmPasswordCtrl,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
            decoration: _inputDecoration(
              hint: '••••••••',
              prefixIcon: const Icon(Icons.lock_clock_outlined, color: AppColors.primary),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textLight),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                tooltip: _obscureConfirmPassword ? 'Show password' : 'Hide password',
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (_confirmPasswordCtrl.text.isNotEmpty)
            Text(
              _passwordCtrl.text == _confirmPasswordCtrl.text
                  ? '✓ Passwords match'
                  : '✕ Passwords do not match',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _passwordCtrl.text == _confirmPasswordCtrl.text ? AppColors.green : AppColors.red,
              ),
            ),
          const SizedBox(height: 16),

          if (!widget.isDirectRegistration && googleEmail.isNotEmpty) ...[
            _inputLabel('Google Account Email (Linked)'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.email_outlined, color: AppColors.textLight, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(googleEmail, style: GoogleFonts.sora(fontSize: 14, color: AppColors.textLight)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (widget.isDirectRegistration) ...[
            _inputLabel('Email Address *'),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: 'your.name@example.com',
                prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textLight),
              ),
            ),
            const SizedBox(height: 16),
          ],

          _inputLabel('Mobile Number (Direct Contact) *'),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10)
            ],
            style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textHead),
            decoration: _inputDecoration(
              hint: '10-digit phone number',
              prefixText: '+91 ',
              prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.textLight),
              counterText: '',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Used for job coordination & phone contact. Never shared without authorization.',
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }

  Widget? _buildUserIdSuffixIcon() {
    switch (_userIdStatus) {
      case UserIdStatus.checking:
        return const SizedBox(width: 20, height: 20, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
      case UserIdStatus.available:
        return const Icon(Icons.check_circle, color: AppColors.green);
      case UserIdStatus.taken:
        return const Icon(Icons.cancel, color: AppColors.red);
      case UserIdStatus.invalid:
        return const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B));
      case UserIdStatus.reserved:
        return const Icon(Icons.lock_outline, color: Color(0xFF6B7280));
      case UserIdStatus.networkError:
        return const Icon(Icons.wifi_off_rounded, color: Color(0xFFF59E0B));
      case UserIdStatus.empty:
        return null;
    }
  }

  // ── Step 2: Skills & Rate (Worker Flow) ──────────────────────────────────
  Widget _skillsPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Trade & Daily Rate',
              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 4),
            Text(
              'ಕೌಶಲ್ಯಗಳು ಮತ್ತು ದಿನದ ಕೂಲಿ — Choose your primary trade and secondary skills.',
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 24),

            _inputLabel('Primary Trade / ಮುಖ್ಯ ಕೌಶಲ್ಯ *'),
            Text(
              'This is your main profession displayed on your worker card and search results.',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kJobCategories.map((cat) {
                final isSelected = _primarySkill == cat.id;
                return ChoiceChip(
                  avatar: Text(cat.emoji, style: const TextStyle(fontSize: 16)),
                  label: Text('${cat.label} (${cat.labelKn})'),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textHead,
                  ),
                  onSelected: (sel) {
                    if (sel) {
                      setState(() {
                        _primarySkill = cat.id;
                        _secondarySkills.remove(cat.id);
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            _inputLabel('Additional Skills / ಹೆಚ್ಚುವರಿ ಕೌಶಲ್ಯಗಳು (Optional)'),
            Text(
              'Select any other work or trades you can perform.',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kJobCategories.where((c) => c.id != _primarySkill).map((cat) {
                final isSelected = _secondarySkills.contains(cat.id);
                return FilterChip(
                  avatar: Text(cat.emoji),
                  label: Text(cat.label),
                  selected: isSelected,
                  selectedColor: AppColors.primaryPale,
                  checkmarkColor: AppColors.primary,
                  side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? AppColors.primary : AppColors.textHead,
                  ),
                  onSelected: (sel) {
                    setState(() {
                      if (sel) {
                        _secondarySkills.add(cat.id);
                      } else {
                        _secondarySkills.remove(cat.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 28),

            _inputLabel('Daily Wage Expectation / ದಿನದ ಕೂಲಿ: ₹${_dailyRate.toInt()}'),
            Slider(
              value: _dailyRate,
              min: 300,
              max: 2500,
              divisions: 44,
              activeColor: AppColors.primary,
              inactiveColor: AppColors.divider,
              onChanged: (v) => setState(() => _dailyRate = v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹300/day', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
                Text('₹2500/day', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
              ],
            ),
            const SizedBox(height: 24),

            _inputLabel('Short Bio / ಪರಿಚಯ (Optional)'),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: 'e.g. 5+ years experience in domestic wiring, switchboards, and emergency repairs. I carry my own standard tools.',
              ),
            ),
          ],
        ),
      );

  // ── Step 3: Experience Level (Worker Flow - Section 12) ──────────────────
  Widget _experiencePage() {
    final levels = [
      {'level': '1-2 yrs', 'title': 'Beginner / ಆರಂಭಿಕ', 'desc': '1 to 2 years hands-on work in trade', 'years': 2},
      {'level': '3-5 yrs', 'title': 'Intermediate / ಮಧ್ಯಮ', 'desc': '3 to 5 years regular independent work', 'years': 4},
      {'level': '5-10 yrs', 'title': 'Experienced / ಅನುಭವಿ', 'desc': '5 to 10 years seasoned craftsman', 'years': 7},
      {'level': '10+ yrs', 'title': 'Senior / ಹಿರಿಯ ತಜ್ಞ', 'desc': '10+ years expert contractor & specialist', 'years': 12},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Experience Level',
            style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead),
          ),
          const SizedBox(height: 4),
          Text(
            'ಅನುಭವದ ಮಟ್ಟ — Highlights your expertise to hirers.',
            style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
          ),
          const SizedBox(height: 24),

          ...levels.map((lvl) {
            final isSelected = _experienceLevel == lvl['level'];
            return GestureDetector(
              onTap: () {
                setState(() {
                  _experienceLevel = lvl['level'] as String;
                  _experienceYears = lvl['years'] as int;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryPale : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        lvl['level'] as String,
                        style: GoogleFonts.sora(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: isSelected ? Colors.white : AppColors.textHead,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lvl['title'] as String,
                            style: GoogleFonts.sora(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textHead,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lvl['desc'] as String,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.textLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isSelected ? AppColors.primary : AppColors.textFaint,
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 20),
          _inputLabel('Exact Total Years: $_experienceYears years'),
          Slider(
            value: _experienceYears.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.divider,
            onChanged: (v) {
              final y = v.toInt();
              setState(() {
                _experienceYears = y;
                if (y <= 2) {
                  _experienceLevel = '1-2 yrs';
                } else if (y <= 5) {
                  _experienceLevel = '3-5 yrs';
                } else if (y <= 10) {
                  _experienceLevel = '5-10 yrs';
                } else {
                  _experienceLevel = '10+ yrs';
                }
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1 year', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
              Text('30+ years', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 4: Service Area & Availability (Worker Flow - Section 13-14) ─────
  Widget _serviceAreaPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Service Area & Reach',
              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 4),
            Text(
              'ಸೇವಾ ಪ್ರದೇಶ ಮತ್ತು ಲಭ್ಯತೆ — Set where you work and your travel distance.',
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 20),

            _inputLabel('District / ಜಿಲ್ಲೆ *'),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _district.isEmpty ? null : _district,
                  hint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select District', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(14),
                  items: KarnatakaLocation.allDistricts.map((d) => DropdownMenuItem(
                    value: d,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(d, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                    ),
                  )).toList(),
                  onChanged: (v) => setState(() {
                    _district = v ?? '';
                    _taluk = '';
                  }),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _inputLabel('Taluk / ತಾಲ್ಲೂಕು'),
            Container(
              decoration: BoxDecoration(
                color: _district.isEmpty ? AppColors.surface2 : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _taluk.isEmpty ? null : _taluk,
                  hint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select Taluk', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  isExpanded: true,
                  disabledHint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select district first', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  items: _district.isEmpty
                      ? null
                      : KarnatakaLocation.taluksForDistrict(_district).map((t) => DropdownMenuItem(
                            value: t,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                            ),
                          )).toList(),
                  onChanged: _district.isEmpty ? null : (v) => setState(() => _taluk = v ?? ''),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _inputLabel('Village / Locality / ಹಳ್ಳಿ (Optional)'),
            TextField(
              controller: _villageCtrl,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: 'e.g. Gandhi Nagar, Kuvempunagar',
                prefixIcon: const Icon(Icons.location_city, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 22),

            _inputLabel('Service Radius / ಸೇವಾ ವ್ಯಾಪ್ತಿ: $_serviceRadiusKm km'),
            Text(
              'How far are you willing to travel for jobs from your location?',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [5, 10, 15, 20, 30].map((km) {
                final isSelected = _serviceRadiusKm == km;
                return ChoiceChip(
                  label: Text('$km km'),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textHead,
                  ),
                  onSelected: (sel) {
                    if (sel) setState(() => _serviceRadiusKm = km);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            _inputLabel('Initial Availability / ಲಭ್ಯತೆ'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Available for Nearby Work',
                  style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                ),
                subtitle: Text(
                  'When enabled, nearby hirers can find you in search. Operational GPS activates only when available.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                ),
                value: _isAvailable,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _isAvailable = v),
              ),
            ),
          ],
        ),
      );

  // ── Step 2: Hirer Location & Business Details ────────────────────────────
  Widget _hirerLocationPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Hiring Location',
              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 4),
            Text(
              'ನೇಮಕ ಪ್ರದೇಶ — Where do you typically need skilled workers?',
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 20),

            _inputLabel('District / ಜಿಲ್ಲೆ *'),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _district.isEmpty ? null : _district,
                  hint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select District', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(14),
                  items: KarnatakaLocation.allDistricts.map((d) => DropdownMenuItem(
                    value: d,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(d, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                    ),
                  )).toList(),
                  onChanged: (v) => setState(() {
                    _district = v ?? '';
                    _taluk = '';
                  }),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _inputLabel('Taluk / ತಾಲ್ಲೂಕು'),
            Container(
              decoration: BoxDecoration(
                color: _district.isEmpty ? AppColors.surface2 : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _taluk.isEmpty ? null : _taluk,
                  hint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select Taluk', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  isExpanded: true,
                  disabledHint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select district first', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  items: _district.isEmpty
                      ? null
                      : KarnatakaLocation.taluksForDistrict(_district).map((t) => DropdownMenuItem(
                            value: t,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                            ),
                          )).toList(),
                  onChanged: _district.isEmpty ? null : (v) => setState(() => _taluk = v ?? ''),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _inputLabel('Locality / Village / Landmark (Optional)'),
            TextField(
              controller: _villageCtrl,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: 'e.g. Ring Road, Near Bus Stand',
                prefixIcon: const Icon(Icons.location_city, color: Color(0xFF7C3AED)),
              ),
            ),
            const SizedBox(height: 20),

            _inputLabel('Household or Business Description (Optional)'),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: 'e.g. Residential home renovation contractor hiring painters and masons.',
              ),
            ),
          ],
        ),
      );

  // ── Step 5 / Step 3: Review Profile (Section 15 & 17) ────────────────────
  Widget _reviewPage() {
    final primaryCategory = kJobCategories.firstWhere(
      (c) => c.id == _primarySkill,
      orElse: () => const JobCategory(id: 'other', label: 'Other', labelKn: 'ಇತರ', emoji: '🔨', color: '#FC8019'),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review Your Details',
            style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead),
          ),
          const SizedBox(height: 4),
          Text(
            'ಪ್ರೊಫೈಲ್ ಪರಿಶೀಲನೆ — Please verify your information before submitting.',
            style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
          ),
          const SizedBox(height: 20),

          // Identity Summary Card
          _reviewCard(
            title: 'Identity',
            onEdit: () => _goToPage(1),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.surface2,
                  backgroundImage: _avatarFile != null
                      ? FileImage(_avatarFile!)
                      : (_avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) as ImageProvider : null),
                  child: (_avatarFile == null && _avatarUrl.isEmpty)
                      ? Text(
                          _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : '?',
                          style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nameCtrl.text.trim(),
                        style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textHead),
                      ),
                      Text(
                        '@${_userIdCtrl.text.trim()}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                      Text(
                        '+91 ${_phoneCtrl.text.trim()}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_role == 'worker') ...[
            const SizedBox(height: 14),
            // Skills & Rate Card
            _reviewCard(
              title: 'Trade & Rates',
              onEdit: () => _goToPage(2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPale,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${primaryCategory.emoji} ${primaryCategory.label}',
                          style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '₹${_dailyRate.toInt()}/day',
                        style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary),
                      ),
                    ],
                  ),
                  if (_secondarySkills.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Secondary Skills:', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _secondarySkills.map((sId) {
                        final cat = kJobCategories.firstWhere(
                          (c) => c.id == sId,
                          orElse: () => const JobCategory(id: '', label: '', labelKn: '', emoji: '', color: '#FC8019'),
                        );
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${cat.emoji} ${cat.label}', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textBody)),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),
            // Experience Card
            _reviewCard(
              title: 'Experience',
              onEdit: () => _goToPage(3),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.violetPale,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _experienceLevel,
                      style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.violet),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$_experienceYears years hands-on work',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),
            // Service Area Card
            _reviewCard(
              title: 'Service Area',
              onEdit: () => _goToPage(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [if (_villageCtrl.text.trim().isNotEmpty) _villageCtrl.text.trim(), if (_taluk.isNotEmpty) _taluk, _district].join(', '),
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Coverage: $_serviceRadiusKm km radius • Available now: ${_isAvailable ? "Yes" : "No"}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            // Hirer Location Card
            _reviewCard(
              title: 'Hiring Location',
              onEdit: () => _goToPage(2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Color(0xFF7C3AED)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [if (_villageCtrl.text.trim().isNotEmpty) _villageCtrl.text.trim(), if (_taluk.isNotEmpty) _taluk, _district].join(', '),
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead),
                        ),
                      ),
                    ],
                  ),
                  if (_bioCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _bioCtrl.text.trim(),
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          // ── Face Verification Requirement Notice (Worker & Hirer) ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _role == 'hirer' ? const Color(0xFFF5F3FF) : AppColors.primaryPale,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _role == 'hirer' ? const Color(0xFF7C3AED).withValues(alpha: 0.3) : AppColors.primaryBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.face_retouching_natural,
                  color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Face Liveness Verification Next',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                        ),
                      ),
                      Text(
                        'ಮುಖ ಪರಿಶೀಲನೆ ಮುಂದಿನ ಹಂತ',
                        style: GoogleFonts.notoSansKannada(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Submitting will launch a quick 5-second selfie blink check to activate your ${_role == 'hirer' ? "hirer" : "worker"} account.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _reviewCard({
    required String title,
    required VoidCallback onEdit,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                GestureDetector(
                  onTap: onEdit,
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Edit', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  // ── Step 6: Confirmation Screen (Section 53 & 54) ─────────────────────────
  Widget _buildConfirmationScreen() => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: const BoxDecoration(
                    color: AppColors.greenPale,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(child: Icon(Icons.check_circle_rounded, color: AppColors.green, size: 54)),
                ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
                const SizedBox(height: 20),

                Text(
                  'Welcome to Kelasagara!',
                  style: GoogleFonts.sora(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textHead),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'ಸ್ವಾಗತ, $_confirmedDisplayName',
                  style: GoogleFonts.notoSansKannada(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Authoritative User ID Badge with Accessible Copy
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primaryBorder),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text('Your Official Kelasagara User ID:', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
                      const SizedBox(height: 6),
                      Text('@$_confirmedUserId', style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: '@$_confirmedUserId'));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('User ID @$_confirmedUserId copied! ✓', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                            backgroundColor: AppColors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ));
                        },
                        icon: const Icon(Icons.copy, size: 16, color: AppColors.primary),
                        label: Text('Copy User ID', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Your profile registration is complete! You can start using your dashboard immediately, or optionally complete face verification for instant recognition.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textLight, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // B12/B13 FIX: Terms & Privacy links
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'By proceeding you agree to our ',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: AppColors.textFaint),
                    ),
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        final uri = Uri.parse('https://kelasagara.in/terms');
                        if (await canLaunchUrl(uri)) {
                          launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Text('Terms',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline)),
                    ),
                    Text(' & ',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: AppColors.textFaint)),
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        final uri = Uri.parse('https://kelasagara.in/privacy');
                        if (await canLaunchUrl(uri)) {
                          launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Text('Privacy Policy',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeShell()),
                        (_) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'Go to Dashboard → / ಮುಂದುವರಿಸಿ',
                      style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _onFinish,
                    icon: const Icon(Icons.face_retouching_natural_outlined, size: 18),
                    label: Text(
                      'Optional: Face Verification (Beta)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _inputLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMed),
        ),
      );

  InputDecoration _inputDecoration({
    required String hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? prefixText,
    String? counterText,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.sora(fontSize: 14, color: AppColors.textFaint),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        prefixText: prefixText,
        counterText: counterText,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      );
}
