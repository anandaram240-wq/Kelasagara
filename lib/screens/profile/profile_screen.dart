// lib/screens/profile/profile_screen.dart
// Production-grade profile hub with section-specific editing for Kelasagara.
// Complies with Sections 38 & 39 of the specification.
// Supports:
//   - Deterministic profile completion tracking
//   - Section-specific editing without restarting onboarding
//   - Avatar photo upload via ProfileMediaService
//   - Skills, experience, service area, and availability updates
//   - Face verification & skill passport status

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../core/constants/karnataka_locations.dart';
import '../../models/user_profile.dart';
import '../../models/hirer_profile_summary.dart';
import '../../services/hirer_profile_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/worker_availability_service.dart';
import '../assessment/skill_passport_screen.dart';
import 'basic_information_screen.dart';
import 'profile_completion_sheet.dart';
import '../../models/worker_reputation.dart';
import '../../services/worker_reputation_service.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../auth/welcome_screen.dart';
import '../settings/voice_accessibility_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _stats;
  WorkerReputationProfile? _reputation;
  HirerProfileSummary? _hirerSummary;
  StreamSubscription<HirerProfileSummary>? _hirerSub;
  String? _hirerUid;
  bool _isReviewsExpanded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void dispose() {
    _hirerSub?.cancel();
    super.dispose();
  }

  void _initHirerStream(String uid) {
    if (_hirerUid == uid && _hirerSub != null) return;
    _hirerUid = uid;
    _hirerSub?.cancel();
    _hirerSub = HirerProfileService.instance.streamHirerProfile(uid).listen(
      (summary) {
        if (mounted) {
          setState(() {
            _hirerSummary = summary;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _hirerSummary = HirerProfileSummary(
              hirerId: uid,
              statistics: const HirerStatistics.zero(),
              isLoading: false,
              error: e.toString(),
            );
          });
        }
      },
    );
  }

  Future<void> _loadStats() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    if (uid == null || uid.isEmpty) return;
    if (auth.isHirer) {
      _initHirerStream(uid);
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      WorkerReputationProfile? rep;
      if (auth.isWorker) {
        rep = await WorkerReputationService.instance.getReputationProfile(uid);
      }
      if (mounted) {
        setState(() {
          if (snap.exists) _stats = snap.data();
          _reputation = rep;
        });
      }
    } catch (_) {}
  }

  void _showToast(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      backgroundColor: isError ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Section Edit Bottom Sheets ─────────────────────────────────────────────

  void _editBasicInfo(UserProfile user) {
    final nameCtrl = TextEditingController(text: user.displayName);
    final bioCtrl = TextEditingController(text: user.bio);
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 0, MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 16),
                Text('Edit Basic Information', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Text('Full Name', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('About / Bio', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                const SizedBox(height: 6),
                TextField(
                  controller: bioCtrl,
                  maxLines: 3,
                  style: GoogleFonts.plusJakartaSans(fontSize: 14),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    hintText: 'Tell customers about your experience and specialty...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: saving ? null : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        _showToast('Name cannot be empty');
                        return;
                      }
                      setModalState(() => saving = true);
                      await context.read<AuthProvider>().updateEditableProfile(
                        displayName: name,
                        bio: bioCtrl.text.trim(),
                      );
                      if (modalCtx.mounted) Navigator.pop(modalCtx);
                      _showToast('Profile updated', isError: false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Save Changes', style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editSkills(UserProfile user) {
    final selectedSkills = Set<String>.from(user.skills);
    double rate = user.dailyRate.toDouble().clamp(300, 5000);
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 16),
              Text('Edit Skills & Daily Rate', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Select the occupations you are skilled in', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight)),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kJobCategories.map((cat) {
                      final sel = selectedSkills.contains(cat.id);
                      return GestureDetector(
                        onTap: () => setModalState(() {
                          if (sel) {
                            if (selectedSkills.length > 1) selectedSkills.remove(cat.id);
                          } else {
                            selectedSkills.add(cat.id);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.primaryPale : AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1),
                          ),
                          child: Text(
                            '${cat.emoji} ${cat.label}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: sel ? AppColors.primary : AppColors.textBody,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Daily Rate', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('₹${rate.toInt()} / day', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary)),
                ],
              ),
              Slider(
                value: rate,
                min: 300,
                max: 3000,
                divisions: 54,
                activeColor: AppColors.primary,
                onChanged: (v) => setModalState(() => rate = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    if (selectedSkills.isEmpty) {
                      _showToast('Select at least one skill');
                      return;
                    }
                    setModalState(() => saving = true);
                    await context.read<AuthProvider>().updateEditableProfile(
                      skills: selectedSkills.toList(),
                      dailyRate: rate.toInt(),
                    );
                    if (modalCtx.mounted) Navigator.pop(modalCtx);
                    _showToast('Skills updated', isError: false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Save Skills', style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editExperience(UserProfile user) {
    final levels = ['1-2 years', '3-5 years', '5-10 years', '10+ years'];
    String selectedLevel = user.experienceLevel.isNotEmpty ? user.experienceLevel : '3-5 years';
    bool saving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 16),
              Text('Edit Experience Level', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('How many years have you worked in your primary field?', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight)),
              const SizedBox(height: 16),
              ...levels.map((lvl) {
                final sel = selectedLevel == lvl;
                return GestureDetector(
                  onTap: () => setModalState(() => selectedLevel = lvl),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primaryPale : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(lvl, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: sel ? AppColors.primary : AppColors.textHead)),
                        if (sel) const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    setModalState(() => saving = true);
                    int years = 1;
                    if (selectedLevel == '3-5 years') years = 3;
                    if (selectedLevel == '5-10 years') years = 5;
                    if (selectedLevel == '10+ years') years = 10;

                    await context.read<AuthProvider>().updateEditableProfile(
                      experienceLevel: selectedLevel,
                      experienceYears: years,
                    );
                    if (modalCtx.mounted) Navigator.pop(modalCtx);
                    _showToast('Experience updated', isError: false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Save Experience', style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editServiceArea(UserProfile user) {
    String district = user.district.isNotEmpty ? user.district : KarnatakaLocation.allDistricts.first;
    String taluk = user.taluk;
    int radius = user.serviceRadiusKm;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final taluks = KarnatakaLocation.taluksForDistrict(district);
          if (!taluks.contains(taluk) && taluks.isNotEmpty) {
            taluk = taluks.first;
          }

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 16),
                Text('Edit Service Area & Coverage', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Text('District', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: district,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  items: KarnatakaLocation.allDistricts.map((d) => DropdownMenuItem(value: d, child: Text(d, style: GoogleFonts.plusJakartaSans(fontSize: 14)))).toList(),
                  onChanged: (v) => setModalState(() {
                    district = v ?? district;
                    taluk = KarnatakaLocation.taluksForDistrict(district).first;
                  }),
                ),
                const SizedBox(height: 14),
                Text('Taluk', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: taluks.contains(taluk) ? taluk : (taluks.isNotEmpty ? taluks.first : null),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  items: taluks.map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 14)))).toList(),
                  onChanged: (v) => setModalState(() => taluk = v ?? taluk),
                ),
                const SizedBox(height: 16),
                Text('Service Radius ($radius km)', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [5, 10, 15, 20, 30].map((km) {
                    final sel = radius == km;
                    return GestureDetector(
                      onTap: () => setModalState(() => radius = km),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primaryPale : AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1),
                        ),
                        child: Text(
                          '$km km',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: sel ? AppColors.primary : AppColors.textBody,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: saving ? null : () async {
                      setModalState(() => saving = true);
                      await context.read<AuthProvider>().updateEditableProfile(
                        district: district,
                        taluk: taluk,
                        serviceRadiusKm: radius,
                      );
                      if (modalCtx.mounted) Navigator.pop(modalCtx);
                      _showToast('Service area updated', isError: false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Save Area', style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final isWorker = auth.isWorker;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final completion = user.calculateProfileCompletion();
    final freshness = WorkerAvailabilityService.checkFreshness(user.discoveryUpdatedAt);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadStats,
        child: CustomScrollView(
          slivers: [
            // ── Top Header with Clean Material 3 Card ──────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(8),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isWorker ? 'Worker Profile' : 'Hirer Profile',
                              style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
                              tooltip: 'Sign Out',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Sign Out'),
                                    content: const Text('Are you sure you want to sign out?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                                        child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true && context.mounted) {
                                  await auth.signOut();
                                  if (context.mounted) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                                      (_) => false,
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Avatar and Worker Identity Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
                              ),
                              child: ClipOval(
                                child: user.photoUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: user.photoUrl,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 180,
                                        memCacheHeight: 180,
                                        errorWidget: (_, __, ___) => _avatarInitial(user),
                                        placeholder: (_, __) => _avatarInitial(user),
                                      )
                                    : _avatarInitial(user),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          user.displayName,
                                          style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (user.accountStatus.value == 'approved') ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.verified, size: 16, color: Color(0xFF2563EB)),
                                      ],
                                    ],
                                  ),
                                  if (user.userId.isNotEmpty)
                                    Text(
                                      '@${user.userId}',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_month_outlined, size: 12, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                      Text(
                                        user.createdAt != null
                                            ? 'Member since ${DateFormat('MMM yyyy').format(user.createdAt!)}'
                                            : 'Kelasagara Member',
                                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.place_outlined, size: 12, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          [user.taluk, user.district].where((s) => s.isNotEmpty).isNotEmpty
                                              ? '${[user.taluk, user.district].where((s) => s.isNotEmpty).join(", ")} • ${user.serviceRadiusKm}km'
                                              : 'Karnataka • ${user.serviceRadiusKm}km coverage',
                                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.translate_outlined, size: 12, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                      Text(
                                        user.languages.isNotEmpty
                                            ? user.languages.join(', ')
                                            : (_stats?['languages'] is List
                                                ? (_stats!['languages'] as List).join(', ')
                                                : 'Kannada, English'),
                                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Stats Summary Row
                        if (isWorker) ...[
                          Row(
                            children: [
                              _headerStatCard(
                                '${user.skills.length} Skills',
                                user.skillVerified ? 'Assessed' : 'Claimed',
                              ),
                              _headerStatCard(
                                '${_reputation?.completedJobs ?? user.totalJobs}',
                                'Completed Jobs',
                              ),
                              _headerStatCard(
                                user.hasReviews || (_reputation?.verifiedReviews ?? 0) > 0
                                    ? '⭐ ${(_reputation?.averageRating ?? user.rating).toStringAsFixed(1)}'
                                    : 'New',
                                '(${_reputation?.verifiedReviews ?? user.totalRatings} Reviews)',
                              ),
                              _headerStatCard(
                                _reputation?.tierDesignation.isEligible == true
                                    ? _reputation!.tierDesignation.tier.displayTitle
                                    : 'Unranked',
                                'Level / Tier',
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ] else ...[
                          Row(
                            children: [
                              _headerStatCard(
                                _hirerSummary?.isLoading == true
                                    ? '...'
                                    : (_hirerSummary?.hasError == true
                                        ? 'Error'
                                        : '${_hirerSummary?.statistics.jobsPosted ?? 0}'),
                                'Jobs Posted',
                              ),
                              _headerStatCard(
                                _hirerSummary?.isLoading == true
                                    ? '...'
                                    : (_hirerSummary?.hasError == true
                                        ? 'Error'
                                        : '${_hirerSummary?.statistics.completedHires ?? 0}'),
                                'Completed Hires',
                              ),
                              _headerStatCard(
                                user.phone.isNotEmpty ? 'Verified' : 'Pending',
                                'Phone Contact',
                              ),
                              _headerStatCard(
                                user.accountStatus.displayLabel,
                                'Hirer Status',
                              ),
                            ],
                          ),
                          if (_hirerSummary?.hasError == true) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFCA5A5)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _hirerSummary!.error ?? 'Could not load hirer statistics',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: const Color(0xFF991B1B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _initHirerStream(auth.uid!),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      'Retry',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFDC2626),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                        ],

                        // Profile Completion Bar (Tap to complete)
                        InkWell(
                          onTap: () => ProfileCompletionSheet.show(
                            context,
                            user: user,
                            onEditBasicInfo: () => _editBasicInfo(user),
                            onEditSkills: () => _editSkills(user),
                            onEditExperience: () => _editExperience(user),
                            onEditServiceArea: () => _editServiceArea(user),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Profile Completion',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                                    ),
                                    Text(
                                      '${completion.percentage}%',
                                      style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF2563EB)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: completion.percentage / 100.0,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    color: const Color(0xFF2563EB),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Section-Specific Profile Cards ───────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile completion nudge (Naukri pattern)
                    if (completion.missingItems.isNotEmpty && completion.percentage < 80) ...[
                      InkWell(
                        onTap: () => ProfileCompletionSheet.show(
                          context,
                          user: user,
                          onEditBasicInfo: () => _editBasicInfo(user),
                          onEditSkills: () => _editSkills(user),
                          onEditExperience: () => _editExperience(user),
                          onEditServiceArea: () => _editServiceArea(user),
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPale,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primaryBorder),
                          ),
                          child: Row(
                            children: [
                              const Text('💡', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Complete your profile',
                                      style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                                    ),
                                    Text(
                                      '${100 - completion.percentage}% left → get 3× more hire requests',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Section 1: Basic Information
                    _sectionHeader('Basic Information'),
                    _profileActionCard(
                      icon: Icons.badge_outlined,
                      title: 'Basic Information',
                      subtitle: 'Personal details, location, languages, and contact',
                      trailingBadge: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Text(
                          'View & Edit',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BasicInformationScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _profileActionCard(
                      icon: Icons.person_outline,
                      title: 'Name & Bio',
                      subtitle: user.bio.isNotEmpty ? user.bio : 'Add a short bio to build customer trust',
                      onTap: () => _editBasicInfo(user),
                    ),

                    const SizedBox(height: 14),

                    // Section 2: Professional Verification & Reputation (Workers Only)
                    if (isWorker) ...[
                      _sectionHeader('Professional Credentials & Reputation'),
                      // Unified Professional Skills Passport
                      _profileActionCard(
                        icon: Icons.badge_outlined,
                        title: 'Professional Skills Passport',
                        subtitle: 'Verified skills, performance, ratings, and work history',
                        trailingBadge: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (_reputation?.tierDesignation.tierColor ?? const Color(0xFF2563EB)).withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: (_reputation?.tierDesignation.tierColor ?? const Color(0xFF2563EB)).withAlpha(80)),
                          ),
                          child: Text(
                            _reputation?.tierDesignation.isEligible == true
                                ? _reputation!.tierDesignation.fullTitle
                                : 'Skills Passport',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _reputation?.tierDesignation.tierColor ?? const Color(0xFF2563EB),
                            ),
                          ),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SkillPassportScreen()),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Section 3: Trade Skills & Rates
                      _sectionHeader('Occupational Skills & Rates'),
                      _profileActionCard(
                        icon: Icons.handyman_outlined,
                        title: 'Skills & Daily Rate',
                        subtitle: user.skills.isNotEmpty
                            ? '${user.skills.length} skills • ₹${user.dailyRate}/day'
                            : 'Set your occupational skills',
                        onTap: () => _editSkills(user),
                      ),

                      const SizedBox(height: 14),

                      // Section 4: Experience
                      _sectionHeader('Work Experience'),
                      _profileActionCard(
                        icon: Icons.work_history_outlined,
                        title: 'Experience Level',
                        subtitle: user.experienceDisplay.isNotEmpty
                            ? user.experienceDisplay
                            : 'Specify your years of practical experience',
                        onTap: () => _editExperience(user),
                      ),

                      const SizedBox(height: 14),
                    ] else ...[
                      // Hirer Activity & Overview
                      _sectionHeader('Hirer Activity & Overview'),
                      _buildHirerOverviewCard(),
                      const SizedBox(height: 12),
                      _buildHirerGivenReviewsCard(),
                      const SizedBox(height: 12),
                      _buildHirerRecentActivityCard(),
                      const SizedBox(height: 12),
                      _profileActionCard(
                        icon: Icons.verified_user_outlined,
                        title: 'Hirer Account Verification',
                        subtitle: user.phone.isNotEmpty
                            ? 'Phone verified (${user.phone}) • Active Hirer'
                            : 'Add mobile phone number to verify account',
                        trailingBadge: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Text(
                            user.phone.isNotEmpty ? 'Verified' : 'Pending',
                            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF059669)),
                          ),
                        ),
                        onTap: () => _editBasicInfo(user),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Section 4: Service Area
                    _sectionHeader('Service Area & Coverage'),
                    _profileActionCard(
                      icon: Icons.location_on_outlined,
                      title: 'Coverage Area',
                      subtitle: [user.taluk, user.district].where((s) => s.isNotEmpty).isNotEmpty
                          ? '${[user.taluk, user.district].where((s) => s.isNotEmpty).join(", ")} (${user.serviceRadiusKm} km radius)'
                          : 'Set district and taluk',
                      onTap: () => _editServiceArea(user),
                    ),

                    const SizedBox(height: 14),

                    // Section 5: Availability (Workers Only)
                    if (isWorker) ...[
                      _sectionHeader('Live Availability'),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: user.isAvailable ? AppColors.green : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.isAvailable ? 'Available for Work' : 'Currently Unavailable',
                                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    user.isAvailable
                                        ? (freshness == LocationFreshness.fresh
                                            ? '🟢 Location fresh • Visible to nearby hirers'
                                            : (freshness == LocationFreshness.recent
                                                ? '🟡 Active recently'
                                                : '🔴 GPS fix needed • Please re-toggle'))
                                        : 'Turn on to let nearby customers find you',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: user.isAvailable,
                              activeThumbColor: AppColors.green,
                              onChanged: (val) async {
                                if (val) {
                                  final res = await WorkerAvailabilityService.instance.setAvailable(
                                    uid: user.uid,
                                    serviceRadiusKm: user.serviceRadiusKm,
                                  );
                                  if (!res.success) {
                                    _showToast(res.errorMessage ?? 'Could not enable availability');
                                  } else {
                                    await auth.updateAvailability(true);
                                  }
                                } else {
                                  await WorkerAvailabilityService.instance.setUnavailable(user.uid);
                                  await auth.updateAvailability(false);
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Verification & Trust
                      _sectionHeader('Identity & Verification'),
                      _profileActionCard(
                        icon: Icons.verified_user_outlined,
                        title: 'Marketplace Trust Status',
                        subtitle: user.accountStatus == AccountStatus.approved
                            ? 'Approved • Verified Member'
                            : user.accountStatus.displayLabel,
                        trailingBadge: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            user.accountStatus.displayLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ),
                        onTap: () {},
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Section 7: App Settings — B07 FIX
                    _sectionHeader('ಸೆಟ್ಟಿಂಗ್ಸ್ / Settings'),
                    _profileActionCard(
                      icon: Icons.tune_outlined,
                      title: 'ಧ್ವನಿ ಮತ್ತು ಪ್ರವೇಶ ಸೆಟ್ಟಿಂಗ್ಸ್ / Voice & Accessibility',
                      subtitle: 'Adjust voice commands, language, and accessibility options',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const VoiceAccessibilitySettingsScreen(),
                        ));
                      },
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarInitial(UserProfile user) {
    final letter = user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'U';
    return Container(
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Text(letter, style: GoogleFonts.sora(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }

  Widget _headerStatCard(String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        title,
        style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textLight),
      ),
    );
  }

  Widget _profileActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailingBadge,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB), size: 20),
          ),
          title: Text(
            title,
            style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
          ),
          subtitle: Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailingBadge != null) ...[
                trailingBadge,
                const SizedBox(width: 6),
              ],
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHirerOverviewCard() {
    final stats = _hirerSummary?.statistics ?? const HirerStatistics.zero();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.analytics_outlined, color: Color(0xFF2563EB), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hiring Overview & Metrics',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                    ),
                    Text(
                      'Authoritative real-time statistics from active records',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _hirerStatChip('📋', '${stats.jobsPosted}', 'Posted', AppColors.primary),
              const SizedBox(width: 6),
              _hirerStatChip('⏳', '${stats.activeJobs}', 'Active', AppColors.violet),
              const SizedBox(width: 6),
              _hirerStatChip('✅', '${stats.filledJobs}', 'Filled', AppColors.green),
              const SizedBox(width: 6),
              _hirerStatChip('💼', '${stats.closedJobs}', 'Closed', const Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              _hirerStatChip('🤝', '${stats.completedHires}', 'Hires', const Color(0xFF0D9488)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hirerStatChip(String emoji, String count, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 2),
            Text(
              count,
              style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w900, color: color),
            ),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHirerRecentActivityCard() {
    final activities = _hirerSummary?.recentActivity ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_rounded, color: Color(0xFF475569), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Activity History',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                    ),
                    Text(
                      'Chronological timeline of jobs, hires, and milestones',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${activities.length} Events',
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (activities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No recent hiring activity recorded yet. Post a job to get started.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
              ),
            )
          else
            Column(
              children: activities.take(4).map((act) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Center(
                          child: Text(act.typeEmoji, style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              act.title,
                              style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                            ),
                            if (act.subtitle != null) ...[
                              const SizedBox(height: 1),
                              Text(
                                act.subtitle!,
                                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('MMM d, yyyy • h:mm a').format(act.timestamp),
                              style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildHirerGivenReviewsCard() {
    final reviews = _hirerSummary?.reviewsGiven ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.star_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Worker Reviews Given',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                    ),
                    Text(
                      'Ratings and feedback submitted for completed jobs',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${reviews.length} Given',
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFFB45309)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No worker reviews submitted yet. Ratings submitted upon mutual work completion will appear here.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
              ),
            )
          else
            Column(
              children: [
                ...(_isReviewsExpanded ? reviews : reviews.take(2)).map((rev) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              rev.workerName,
                              style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '• ${rev.jobTitle}',
                                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              children: List.generate(5, (i) {
                                final starVal = (i + 1).toDouble();
                                return Icon(
                                  starVal <= rev.stars ? Icons.star_rounded : Icons.star_border_rounded,
                                  color: const Color(0xFFF59E0B),
                                  size: 14,
                                );
                              }),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rev.stars.toStringAsFixed(1),
                              style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
                            ),
                          ],
                        ),
                        if (rev.hasFeedback) ...[
                          const SizedBox(height: 6),
                          Text(
                            '"${rev.feedback!}"',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF334155), fontStyle: FontStyle.italic),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Booking: #${rev.bookingId.length > 12 ? rev.bookingId.substring(0, 12) : rev.bookingId}',
                              style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF94A3B8)),
                            ),
                            Text(
                              DateFormat('MMM d, yyyy').format(rev.createdAt),
                              style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                if (reviews.length > 2)
                  InkWell(
                    onTap: () => setState(() => _isReviewsExpanded = !_isReviewsExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isReviewsExpanded ? 'Show Less' : 'View All ${reviews.length} Reviews',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF2563EB)),
                          ),
                          Icon(
                            _isReviewsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            size: 18,
                            color: const Color(0xFF2563EB),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
