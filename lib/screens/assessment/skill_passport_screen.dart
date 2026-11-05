// lib/screens/assessment/skill_passport_screen.dart
// ============================================================================
// KELASAGARA — UNIFIED PROFESSIONAL SKILLS PASSPORT
// Complete, consolidated, scrollable worker identity, skills, performance,
// work history, ratings, reliability, achievements and public sharing.
// Zero tabs, zero blank/gray screens, pull-to-refresh, privacy-safe.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_colors.dart';
import '../../models/user_profile.dart';
import '../../models/worker_reputation.dart';
import '../../models/skill_badge.dart';
import '../../models/public_worker_passport.dart';
import '../../services/worker_reputation_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/passport_qr_widget.dart';

class SkillPassportScreen extends StatefulWidget {
  const SkillPassportScreen({super.key});

  @override
  State<SkillPassportScreen> createState() => _SkillPassportScreenState();
}

class _SkillPassportScreenState extends State<SkillPassportScreen> {
  WorkerReputationProfile? _reputation;
  List<SkillBadge> _badges = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final uid = auth.uid ?? '';
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Worker authentication required.';
        });
      }
      return;
    }

    try {
      final rep = await WorkerReputationService.instance.getReputationProfile(uid);
      final user = auth.currentUser;
      final userMap = user != null
          ? {
              'phone': user.phone,
              'faceVerified': user.faceVerified,
              'accountStatus': user.accountStatus.value,
              'createdAt': user.createdAt,
            }
          : <String, dynamic>{};

      final badges = await WorkerReputationService.instance.getEarnedBadges(
        workerId: uid,
        userData: userMap,
        reputation: rep,
      );

      if (mounted) {
        setState(() {
          _reputation = rep;
          _badges = badges;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _showShareQrModal(BuildContext context, String workerId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PassportShareSheet(workerId: workerId),
    );
  }

  void _showCertificateDialog(BuildContext context, WorkerReputationProfile rep) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(22),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFFAF5FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFF7C3AED), size: 40),
            ),
            const SizedBox(height: 12),
            Text(
              'KELASAGARA ELITE',
              style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFF7C3AED), letterSpacing: 1.5),
            ),
            const SizedBox(height: 4),
            Text(
              'MASTER CRAFTSWORKER',
              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 8),
            Text(
              'This certifies sustained Diamond performance, verified trade skill competence, and exceptional customer satisfaction across 75+ completed jobs.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textMed, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                rep.eliteRecognition.disclaimer,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight, height: 1.3),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Close Certificate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text(
            'Authentication required to view Skills Passport',
            style: GoogleFonts.plusJakartaSans(color: AppColors.textMed),
          ),
        ),
      );
    }

    final primarySkill = user.skills.isNotEmpty ? user.skills.first : 'General Services';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        top: false,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                floating: true,
                pinned: false,
                snap: true,
                backgroundColor: Colors.white,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                title: Text(
                  'Professional Skills Passport',
                  style: GoogleFonts.sora(
                    color: AppColors.textHead,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                iconTheme: const IconThemeData(color: AppColors.textHead),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.qr_code_2_rounded, color: AppColors.primary),
                    tooltip: 'Share Passport QR',
                    onPressed: () => _showShareQrModal(context, user.uid),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(color: AppColors.divider, height: 1),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── 1. PROFESSIONAL IDENTITY HERO ──────────────────────────────
                    _buildIdentityHeroCard(user, primarySkill),
                    const SizedBox(height: 20),

                    // ── 2. PROFESSIONAL SKILLS & RATES ─────────────────────────────
                    _buildSkillsSection(user),
                    const SizedBox(height: 20),

                    // ── 3. WORK HISTORY ────────────────────────────────────────────
                    _buildWorkHistorySection(user.uid),
                    const SizedBox(height: 20),

                    // ── 4. WORK PERFORMANCE ────────────────────────────────────────
                    _buildPerformanceSection(),
                    const SizedBox(height: 20),

                    // ── 5. RATINGS & REVIEWS ───────────────────────────────────────
                    _buildReviewsSection(user.uid),
                    const SizedBox(height: 20),

                    // ── 6. RELIABILITY BREAKDOWN ───────────────────────────────────
                    _buildReliabilitySection(),
                    const SizedBox(height: 20),

                    // ── 7. ACHIEVEMENTS & TIERS ────────────────────────────────────
                    _buildAchievementsAndTiersSection(user),
                    const SizedBox(height: 20),

                    // ── 8. PUBLIC PASSPORT SHARING ─────────────────────────────────
                    _buildPublicPassportSharingCard(user),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // SECTION 1: PROFESSIONAL IDENTITY HERO CARD
  // ==========================================================================
  Widget _buildIdentityHeroCard(UserProfile user, String primarySkill) {
    final rep = _reputation;
    final isEligible = rep?.tierDesignation.isEligible == true;
    final tierTitle = isEligible ? (rep?.tierDesignation.fullTitle ?? 'Worker') : 'Not Yet Ranked (In Training)';
    final tierColor = isEligible ? (rep?.tierDesignation.tierColor ?? const Color(0xFF64748B)) : const Color(0xFF64748B);

    final locationText = [user.taluk, user.district].where((s) => s.isNotEmpty).isNotEmpty
        ? '${[user.taluk, user.district].where((s) => s.isNotEmpty).join(", ")} • ${user.serviceRadiusKm}km coverage'
        : 'Karnataka • ${user.serviceRadiusKm}km coverage';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
                ),
                child: ClipOval(
                  child: user.photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: user.photoUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          memCacheHeight: 160,
                          placeholder: (_, __) => _avatarInitial(user),
                          errorWidget: (_, __, ___) => _avatarInitial(user),
                        )
                      : _avatarInitial(user),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.displayName.isNotEmpty ? user.displayName : 'Worker Profile',
                            style: GoogleFonts.sora(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textHead,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user.accountStatus.value == 'approved') ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, size: 16, color: Color(0xFF2563EB)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      primarySkill,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.place_outlined, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locationText,
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tierColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tierColor.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isEligible ? Icons.workspace_premium_rounded : Icons.school_outlined,
                      size: 13,
                      color: tierColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      tierTitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: tierColor,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'ID: KL-${user.uid.substring(0, user.uid.length >= 6 ? 6 : user.uid.length).toUpperCase()}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showShareQrModal(context, user.uid),
              icon: const Icon(Icons.qr_code_2_rounded, size: 18, color: AppColors.primary),
              label: Text(
                'Share Public Passport / QR',
                style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primaryBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarInitial(UserProfile user) {
    final initial = user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'W';
    return Container(
      color: const Color(0xFFF1F5F9),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.sora(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFF475569)),
      ),
    );
  }

  // ==========================================================================
  // SECTION 2: PROFESSIONAL SKILLS & RATES
  // ==========================================================================
  Widget _buildSkillsSection(UserProfile user) {
    final skills = user.skills;
    final rateStr = user.dailyRate > 0 ? '₹${user.dailyRate}/day' : 'Market Standard';
    final expStr = user.experienceYears > 0
        ? '${user.experienceYears} Years Experience'
        : (user.experienceLevel.isNotEmpty ? user.experienceLevel : 'Experienced');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                child: const Icon(Icons.handyman_outlined, size: 18, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Professional Skills & Rates',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Worker-declared trade skills and daily rate',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Skills and rates are declared by the worker and verified through completed jobs and hirer ratings.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF64748B), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (skills.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Icon(Icons.build_circle_outlined, size: 36, color: Color(0xFFCBD5E1)),
                  const SizedBox(height: 8),
                  Text(
                    'No trade skills added yet',
                    style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add your trade skills in Profile to start receiving job matches',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                  ),
                ],
              ),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: skills.map((skill) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF2563EB)),
                      const SizedBox(width: 6),
                      Text(
                        skill,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHead),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Standard Rate', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
                        const SizedBox(height: 2),
                        Text(rateStr, style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Experience', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
                        const SizedBox(height: 2),
                        Text(expStr, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // SECTION 3: WORK HISTORY (MUTUALLY CONFIRMED COMPLETED JOBS)
  // ==========================================================================
  Widget _buildWorkHistorySection(String workerId) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.work_history_outlined, size: 18, color: Color(0xFF16A34A)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Work History',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Mutually confirmed completed bookings',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<PublicWorkRecord>>(
            stream: WorkerReputationService.instance.streamWorkHistory(workerId),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _buildSkeletonLoader(itemCount: 2);
              }

              if (snap.hasError) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Work history is synchronizing. Completed jobs will reflect shortly.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textHead),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final records = snap.data ?? [];
              if (records.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.assignment_turned_in_outlined, size: 36, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 8),
                      Text(
                        'No Confirmed Completed Jobs Yet',
                        style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'When a hirer completes a booking and mutual arrival is verified, the verified job record appears here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: records.take(5).map((rec) {
                  final dateFormatted = DateFormat('dd MMM yyyy').format(rec.completionDate);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              rec.jobCategory,
                              style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF86EFAC)),
                              ),
                              child: Text(
                                rec.bookingStatus == 'completion_verified' ? 'Mutually Confirmed' : 'Completed',
                                style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF15803D)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 11, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(dateFormatted, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
                            const SizedBox(width: 12),
                            Icon(Icons.place_outlined, size: 11, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(rec.generalizedArea, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
                          ],
                        ),
                        if (rec.ratingStars != null && rec.ratingStars! > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 4),
                              Text(
                                '${rec.ratingStars!.toStringAsFixed(1)} ★ Rated by Hirer',
                                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFB45309)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SECTION 4: WORK PERFORMANCE
  // ==========================================================================
  Widget _buildPerformanceSection() {
    if (_loading) {
      return _buildSkeletonLoader(itemCount: 2);
    }

    final rep = _reputation;
    if (_error != null || rep == null) {
      return _buildInlineErrorCard('Unable to load performance metrics', _error ?? 'Network error');
    }

    final opi = rep.performanceIndex.compositeIndex;
    final opiColor = opi >= 75 ? const Color(0xFF16A34A) : (opi >= 50 ? const Color(0xFFD97706) : const Color(0xFF64748B));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                child: const Icon(Icons.speed_rounded, size: 18, color: Color(0xFFD97706)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Work Performance',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Operational reliability and overall rating quality',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // OPI Highlight Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Overall Performance Index',
                      style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: opiColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: opiColor.withAlpha(80)),
                      ),
                      child: Text(
                        '${opi.toStringAsFixed(1)} / 100',
                        style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w900, color: opiColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (opi / 100.0).clamp(0.0, 1.0),
                    backgroundColor: const Color(0xFFE2E8F0),
                    color: opiColor,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0 (Entry)', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
                    Text(
                      rep.completedJobs < 3 ? 'Preliminary (Under 3 jobs)' : 'Standard Evaluated',
                      style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: opiColor),
                    ),
                    Text('100 (Master)', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Operational Metrics Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF16A34A),
                  title: 'Completed Jobs',
                  value: '${rep.completedJobs}',
                  subtitle: 'Mutually verified',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.star_rounded,
                  color: const Color(0xFFF59E0B),
                  title: 'Average Rating',
                  value: '${rep.averageRating.toStringAsFixed(1)} ★',
                  subtitle: '${rep.verifiedReviews} reviews',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.verified_user_outlined,
                  color: const Color(0xFF2563EB),
                  title: 'Bayesian Quality',
                  value: '${rep.bayesianRating.adjustedRating.toStringAsFixed(2)} ★',
                  subtitle: 'Priors adjusted',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.access_time_rounded,
                  color: const Color(0xFF7C3AED),
                  title: 'On-Time Arrival',
                  value: rep.performanceIndex.hasOnTimeData ? '${rep.performanceIndex.onTimeArrivalScore.toStringAsFixed(0)}%' : 'N/A',
                  subtitle: rep.performanceIndex.hasOnTimeData ? '${rep.onTimeArrivals} of ${rep.totalMeasuredArrivals} arrivals' : 'Needs ≥3 arrivals',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMed),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead),
          ),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SECTION 5: RATINGS & REVIEWS
  // ==========================================================================
  Widget _buildReviewsSection(String workerId) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                child: const Icon(Icons.rate_review_outlined, size: 18, color: Color(0xFFD97706)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ratings & Feedback',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Direct feedback left by confirmed hirers',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<PublicHirerReview>>(
            stream: WorkerReputationService.instance.streamReviews(workerId),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _buildSkeletonLoader(itemCount: 2);
              }

              if (snap.hasError) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Hirer reviews syncing with ledger.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMed),
                  ),
                );
              }

              final reviews = snap.data ?? [];
              if (reviews.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.star_outline_rounded, size: 36, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 8),
                      Text(
                        'No Reviews Received Yet',
                        style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ratings and written feedback left by hirers will be published here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: reviews.take(5).map((rev) {
                  final dateFormatted = DateFormat('dd MMM yyyy').format(rev.reviewDate);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: List.generate(5, (index) {
                                return Icon(
                                  index < rev.stars.floor() ? Icons.star_rounded : Icons.star_border_rounded,
                                  size: 14,
                                  color: const Color(0xFFF59E0B),
                                );
                              }),
                            ),
                            Text(dateFormatted, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (rev.publicFeedback.isNotEmpty) ...[
                          Text(
                            '"${PublicHirerReview.scrubSensitiveContent(rev.publicFeedback)}"',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textHead,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              rev.jobCategory,
                              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                            Text(
                              rev.raterRole,
                              style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SECTION 6: RELIABILITY BREAKDOWN
  // ==========================================================================
  Widget _buildReliabilitySection() {
    if (_loading) {
      return _buildSkeletonLoader(itemCount: 2);
    }

    final rep = _reputation;
    if (rep == null) return const SizedBox.shrink();

    final isSampleLow = rep.completedJobs < 3;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                child: const Icon(Icons.shield_outlined, size: 18, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reliability Breakdown',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Individual reliability dimensions and sample counts',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (isSampleLow) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Preliminary Data: Minimum 3 completed jobs required to calculate standard baseline reliability. Complete ${3 - rep.completedJobs} more job(s) to establish your score.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF92400E), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          _buildReliabilityRow(
            title: 'On-Time Arrival',
            score: rep.performanceIndex.hasOnTimeData ? rep.performanceIndex.onTimeArrivalScore : 100.0,
            sample: rep.performanceIndex.hasOnTimeData ? '${rep.onTimeArrivals} on-time of ${rep.totalMeasuredArrivals} arrivals' : 'Threshold: ≥ 3 arrivals',
            isEligible: rep.performanceIndex.hasOnTimeData,
          ),
          const Divider(height: 16, color: Color(0xFFF1F5F9)),
          _buildReliabilityRow(
            title: 'Job Completion Rate',
            score: rep.performanceIndex.completionReliabilityScore,
            sample: '${rep.completedJobs} mutually completed vs ${rep.disputedJobs} disputed',
            isEligible: true,
          ),
          const Divider(height: 16, color: Color(0xFFF1F5F9)),
          _buildReliabilityRow(
            title: 'Cancellation Avoidance',
            score: rep.performanceIndex.cancellationReliabilityScore,
            sample: '${rep.workerCancellations} worker cancellations',
            isEligible: true,
          ),
          const Divider(height: 16, color: Color(0xFFF1F5F9)),
          _buildReliabilityRow(
            title: 'Repeat Hirer Retention',
            score: rep.performanceIndex.hasRepeatHirerData ? rep.performanceIndex.repeatHirerScore : 0.0,
            sample: rep.performanceIndex.hasRepeatHirerData ? '${rep.repeatHirers} repeat clients out of ${rep.uniqueHirers} unique' : 'Threshold: ≥ 3 hirers',
            isEligible: rep.performanceIndex.hasRepeatHirerData,
          ),
        ],
      ),
    );
  }

  Widget _buildReliabilityRow({
    required String title,
    required double score,
    required String sample,
    required bool isEligible,
  }) {
    final color = score >= 80 ? const Color(0xFF16A34A) : (score >= 60 ? const Color(0xFFD97706) : const Color(0xFFDC2626));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHead)),
            Text(sample, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
          ],
        ),
        Text(
          isEligible ? '${score.toStringAsFixed(0)}%' : 'Pending Data',
          style: GoogleFonts.sora(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: isEligible ? color : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // SECTION 7: ACHIEVEMENTS & 5-TIER REPUTATION
  // ==========================================================================
  Widget _buildAchievementsAndTiersSection(UserProfile user) {
    if (_loading) {
      return _buildSkeletonLoader(itemCount: 2);
    }

    final rep = _reputation;
    if (rep == null) return const SizedBox.shrink();

    final isEligible = rep.tierDesignation.isEligible;
    final tier = rep.tierDesignation.tier;
    final nextReq = rep.getNextLevelRequirements();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.military_tech_outlined, size: 18, color: Color(0xFF7C3AED)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Achievements & Reputation Tier',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Earned milestones and verified recognition',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Current Tier Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isEligible ? tier.badgeBg : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isEligible ? tier.borderColor : const Color(0xFFCBD5E1),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEligible ? tier.displayName : 'Not Yet Ranked (In Training)',
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isEligible ? tier.primaryColor : const Color(0xFF475569),
                      ),
                    ),
                    if (isEligible)
                      Text(
                        rep.tierDesignation.fullTitle,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: tier.primaryColor),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isEligible
                      ? 'Earned through verified performance and customer satisfaction.'
                      : 'Complete initial jobs and receive hirer ratings to unlock Bronze recognition.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMed),
                ),
                if (!isEligible) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 10),
                  Text(
                    'Roadmap to Bronze Ranking:',
                    style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textHead),
                  ),
                  const SizedBox(height: 6),
                  _buildRequirementItem('Completed Jobs', '${rep.completedJobs} / 3', rep.completedJobs >= 3),
                  _buildRequirementItem('Unique Hirers', '${rep.uniqueHirers} / 2', rep.uniqueHirers >= 2),
                  _buildRequirementItem('Hirer Reviews', '${rep.verifiedReviews} / 1', rep.verifiedReviews >= 1),
                  _buildRequirementItem('OPI Score', '${rep.performanceIndex.compositeIndex.toStringAsFixed(1)} / 60.0', rep.performanceIndex.compositeIndex >= 60.0),
                ] else if (nextReq['hasNextTier'] == true) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 10),
                  Text(
                    'Requirements for ${nextReq['nextTitle']}:',
                    style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textHead),
                  ),
                  const SizedBox(height: 6),
                  _buildRequirementItem('Jobs Required', 'Need ${nextReq['jobsNeeded']} more jobs', (nextReq['jobsNeeded'] as int? ?? 0) <= 0),
                  _buildRequirementItem('Minimum OPI', 'Need ${nextReq['pointsNeeded']} index pts', (double.tryParse(nextReq['pointsNeeded']?.toString() ?? '0') ?? 0.0) <= 0.0),
                ],
              ],
            ),
          ),

          // Master Craftsworker Card if unlocked
          if (rep.eliteRecognition.isAwarded) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _showCertificateDialog(context, rep),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD8B4FE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: Color(0xFF7C3AED), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Master Craftsworker Recognition', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF7C3AED))),
                          Text('Tap to inspect verified certificate', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF7C3AED)),
                  ],
                ),
              ),
            ),
          ],

          // Earned Badges
          if (_badges.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Earned Badges (${_badges.length})',
              style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textHead),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _badges.map((b) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.military_tech_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        b.type.displayName,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHead),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequirementItem(String label, String value, bool achieved) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                achieved ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 13,
                color: achieved ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMed)),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: achieved ? const Color(0xFF16A34A) : AppColors.textHead,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SECTION 8: PUBLIC PASSPORT SHARING
  // ==========================================================================
  Widget _buildPublicPassportSharingCard(UserProfile user) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                child: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Public Verification & QR',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Share your verified credentials with any hirer',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Hirers can scan your public QR code to inspect your verified skills, completed work ledger, and reputation without accessing personal contact information or home address.',
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMed, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _showShareQrModal(context, user.uid),
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: Text(
                'Open Public Share QR Code',
                style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SHARED SKELETON & ERROR HELPERS (ZERO BLANK/GRAY SCREENS)
  // ==========================================================================
  Widget _buildSkeletonLoader({int itemCount = 3}) {
    return Column(
      children: List.generate(itemCount, (i) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
        );
      }),
    );
  }

  Widget _buildInlineErrorCard(String title, String details) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            details,
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try Again / ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PUBLIC PASSPORT SHARE SHEET (REVOCABLE SECURE TOKEN + QR WIDGET)
// ============================================================================
class _PassportShareSheet extends StatefulWidget {
  final String workerId;
  const _PassportShareSheet({required this.workerId});

  @override
  State<_PassportShareSheet> createState() => _PassportShareSheetState();
}

class _PassportShareSheetState extends State<_PassportShareSheet> {
  bool _loading = true;
  bool _isSharingEnabled = false;
  String? _shareToken;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _fetchSharingState();
  }

  Future<void> _fetchSharingState() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.workerId).get();
      final data = doc.data() ?? {};
      if (mounted) {
        setState(() {
          _isSharingEnabled = data['isSharingEnabled'] == true || data['publicSharingEnabled'] == true;
          _shareToken = data['publicShareToken'] as String?;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enableSharing() async {
    setState(() => _actionInProgress = true);
    try {
      final token = await WorkerReputationService.instance.enablePublicSharing(widget.workerId);
      if (mounted) {
        setState(() {
          _isSharingEnabled = true;
          _shareToken = token;
          _actionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Public sharing enabled with secure link', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to enable sharing: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _revokeSharing() async {
    setState(() => _actionInProgress = true);
    try {
      await WorkerReputationService.instance.revokePublicSharing(widget.workerId);
      if (mounted) {
        setState(() {
          _isSharingEnabled = false;
          _shareToken = null;
          _actionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Public sharing link revoked immediately', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to revoke sharing: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final verifyUrl = (_isSharingEnabled && _shareToken != null && _shareToken!.isNotEmpty)
        ? 'https://kelasagara-f127a.web.app/verify/$_shareToken'
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Public Skills Passport',
            style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textHead),
          ),
          const SizedBox(height: 6),
          Text(
            _isSharingEnabled
                ? 'Hirers can scan this code to inspect your verified skills, completed work ledger, and reputation without accessing personal contact information.'
                : 'Your skills passport is private by default. You can enable public sharing to generate a secure, revocable link for hirers.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight, height: 1.4),
          ),
          const SizedBox(height: 20),

          if (_isSharingEnabled && verifyUrl.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: PassportQrWidget(
                verificationUrl: verifyUrl,
                size: 200,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              verifyUrl,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: const Color(0xFF2563EB),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: verifyUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Verification link copied to clipboard!', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                          backgroundColor: const Color(0xFF16A34A),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy Link'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _actionInProgress ? null : _revokeSharing,
                    icon: const Icon(Icons.link_off_rounded, size: 16),
                    label: const Text('Revoke'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _actionInProgress ? null : _enableSharing,
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(
                  _actionInProgress ? 'Generating...' : 'Enable Public Sharing & QR',
                  style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
