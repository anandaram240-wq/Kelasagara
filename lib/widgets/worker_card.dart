// lib/widgets/worker_card.dart
// Premium Worker Profile Card for Kelasagara.
// Strictly complies with Sections 23-33 of the specification.
// Information Hierarchy:
//   1. Avatar + Name + Primary Skill + Verification Badges
//   2. Live Freshness-aware Availability Dot
//   3. Truthful Rating (never 5.0 for 0 reviews) + Total Jobs + Rate
//   4. Experience Pill (e.g. "5+ years")
//   5. Primary + 2 Secondary Skills + "+N more" badge
//   6. Geo Distance + Road Distance & ETA (from MatrixService)
//   7. Service Area (taluk, district)
//   8. View Profile & Message action buttons
import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/constants/job_categories.dart';
import '../models/user_profile.dart';
import '../models/worker_search_result.dart';
import '../providers/auth_provider.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/profile/worker_profile_detail_screen.dart';
import '../services/chat_booking_service.dart';
import '../services/worker_availability_service.dart';

class WorkerCard extends StatelessWidget {
  final UserProfile worker;
  final double? distanceKm; // straight-line distance fallback
  final VoidCallback? onMessage;
  final VoidCallback? onViewProfile;
  final int index; // for staggered animation
  final WorkerSearchEntry? searchEntry; // Phase 3: full search entry with geo/road/ETA data

  const WorkerCard({
    super.key,
    required this.worker,
    this.distanceKm,
    this.onMessage,
    this.onViewProfile,
    this.index = 0,
    this.searchEntry,
  });

  void _openProfile(BuildContext context) {
    if (onViewProfile != null) {
      onViewProfile!();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkerProfileDetailScreen(
            worker: worker,
            searchEntry: searchEntry,
          ),
        ),
      );
    }
  }

  Future<void> _handleDefaultMessage(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to message this worker')),
      );
      return;
    }
    if (auth.uid == worker.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot message yourself')),
      );
      return;
    }

    try {
      final skillTitle = worker.skills.isNotEmpty ? worker.skills.first : 'Service Inquiry';
      await ChatService.getOrCreate(
        myUid: auth.uid!,
        otherUid: worker.uid,
        jobId: 'direct_${worker.uid}',
        myName: auth.name,
        otherName: worker.displayName,
        jobTitle: 'Direct Hire: $skillTitle',
      );

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            workerName: worker.displayName,
            jobTitle: 'Direct Hire: $skillTitle',
            otherUserId: worker.uid,
            jobId: 'direct_${worker.uid}',
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start conversation')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Skills taxonomy resolution
    final allSkills = worker.skills
        .map((id) {
          try {
            return kJobCategories.firstWhere((c) => c.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<JobCategory>()
        .toList();

    final visibleSkills = allSkills.take(3).toList();
    final overflowCount = allSkills.length > 3 ? allSkills.length - 3 : 0;

    // Freshness & Availability calculation
    final freshness = WorkerAvailabilityService.checkFreshness(worker.discoveryUpdatedAt);
    final bool isAvailableNow = worker.isAvailable && freshness != LocationFreshness.stale;
    final bool isFresh = worker.isAvailable && freshness == LocationFreshness.fresh;
    final String availabilityLabel = isAvailableNow
        ? (isFresh ? 'Available now' : 'Active recently')
        : 'Busy';
    final Color availabilityColor = isFresh ? AppColors.green
        : isAvailableNow ? const Color(0xFF6B7280)
        : const Color(0xFF9CA3AF);
    final Color avatarRingColor = isFresh ? AppColors.green
        : isAvailableNow ? const Color(0xFF6B7280)
        : Colors.transparent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openProfile(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row: Avatar + Name & Handle + Availability Dot ─────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar (64dp with graceful fallback) + availability ring
                    GestureDetector(
                      onTap: () => _openProfile(context),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: avatarRingColor,
                                width: isFresh ? 2.5 : 0,
                              ),
                            ),
                            child: _buildAvatar(),
                          ),
                          // Availability dot
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: availabilityColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Name + Primary Skill / Badges
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            worker.displayName,
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textHead,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@${worker.userId}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Trust & Verification Badges
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (worker.faceVerified)
                                _badge('✅ Verified', AppColors.green),
                              if (worker.skillVerified)
                                _badge('🏆 Certified', AppColors.violet),
                              if (worker.experienceDisplay.isNotEmpty)
                                _badge('⏱ ${worker.experienceDisplay}', AppColors.primary),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Availability pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: availabilityColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: availabilityColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: availabilityColor, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text(availabilityLabel, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: availabilityColor)),
                      ]),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Stats row: Truthful Ratings + Jobs + Rate ─────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Truthful rating
                      _statItem(
                        '⭐',
                        worker.totalRatings > 0
                            ? '${worker.rating.toStringAsFixed(1)} (${worker.totalRatings})'
                            : 'No reviews',
                        highlight: worker.totalRatings > 0,
                      ),
                      _dividerDot(),
                      _statItem('💼', '${worker.totalJobs} jobs'),
                      _dividerDot(),
                      _statItem('💰', '₹${worker.dailyRate}/day'),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ── Skills Chips (Primary + 2 Secondary + Overflow) ───────────
                if (visibleSkills.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ...visibleSkills.map((cat) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${cat.emoji} ${cat.label}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      )),
                      if (overflowCount > 0)
                        GestureDetector(
                          onTap: () => _openProfile(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              '+$overflowCount more',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textLight,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                // ── Road Distance + ETA (Phase 3 Matrix) ──────────────────────
                if (searchEntry != null &&
                    (searchEntry!.roadDistanceM != null || searchEntry!.etaNote.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (searchEntry!.roadDistanceM != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.violetPale,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '🚦 ${(searchEntry!.roadDistanceM! / 1000).toStringAsFixed(1)} km by road',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.violet,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (searchEntry!.etaNote.isNotEmpty &&
                          searchEntry!.etaNote != 'Road ETA unavailable')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPale,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '⏱ ${searchEntry!.etaNote}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                // ── Declared Service Area & Straight-line Distance ────────────
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textLight),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [worker.taluk, worker.district].where((s) => s.isNotEmpty).join(' · '),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textLight,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (searchEntry?.geoDistanceKm != null)
                      Text(
                        '${searchEntry!.geoDistanceKm!.toStringAsFixed(1)} km away',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else if (distanceKm != null)
                      Text(
                        '${distanceKm!.toStringAsFixed(1)} km away',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── Action Buttons ───────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          if (onMessage != null) {
                            onMessage!();
                          } else {
                            _handleDefaultMessage(context);
                          }
                        },
                        icon: const Icon(Icons.chat_bubble_outline, size: 15),
                        label: Text(
                          'Message',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _openProfile(context),
                        icon: const Icon(Icons.person_outline, size: 15, color: Colors.white),
                        label: Text(
                          'View Profile',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms, delay: Duration(milliseconds: index * 60)).slideY(begin: 0.08, end: 0);
  }

  Widget _buildAvatar() {
    final hasPhoto = worker.photoUrl.isNotEmpty;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: hasPhoto ? null : const LinearGradient(
          colors: [Color(0xFFFC8019), Color(0xFFFFA44D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: hasPhoto
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CachedNetworkImage(
                imageUrl: worker.photoUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                memCacheWidth: 128,
                memCacheHeight: 128,
                errorWidget: (_, __, ___) => _avatarFallback(),
                placeholder: (_, __) => _avatarFallback(),
              ),
            )
          : _avatarFallback(),
    );
  }

  Widget _avatarFallback() {
    final letter = worker.displayName.isNotEmpty
        ? worker.displayName[0].toUpperCase()
        : '?';
    return Center(
      child: Text(
        letter,
        style: GoogleFonts.sora(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _statItem(String emoji, String text, {bool highlight = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
            color: highlight ? AppColors.primary : AppColors.textHead,
          ),
        ),
      ],
    );
  }

  Widget _dividerDot() {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(
        color: AppColors.textLight,
        shape: BoxShape.circle,
      ),
    );
  }
}
