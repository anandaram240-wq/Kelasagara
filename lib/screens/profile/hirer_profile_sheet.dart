// lib/screens/profile/hirer_profile_sheet.dart
// Premium Hirer Public Profile Sheet for Kelasagara Phase 5.
// Displays the Hirer's verified identity, posting history, ratings, and reputation.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_profile.dart';
import '../../models/hirer_profile_summary.dart';
import '../../services/hirer_profile_service.dart';
import '../chat/chat_screen.dart';

class HirerPublicProfileSheet extends StatelessWidget {
  final String hirerId;
  final String fallbackName;

  const HirerPublicProfileSheet({
    super.key,
    required this.hirerId,
    this.fallbackName = 'Hirer',
  });

  static void show(BuildContext context, {required String hirerId, String fallbackName = 'Hirer'}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HirerPublicProfileSheet(hirerId: hirerId, fallbackName: fallbackName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: FutureBuilder<List<dynamic>>(
          future: Future.wait([
            FirebaseFirestore.instance.collection('users').doc(hirerId).get(),
            HirerProfileService.instance.getHirerProfile(hirerId),
          ]),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            UserProfile? profile;
            HirerProfileSummary? summary;

            if (snap.hasData && snap.data!.length >= 2) {
              final userDoc = snap.data![0] as DocumentSnapshot;
              if (userDoc.exists && userDoc.data() != null) {
                profile = UserProfile.fromMap(userDoc.id, userDoc.data() as Map<String, dynamic>);
              }
              summary = snap.data![1] as HirerProfileSummary;
            }

            final name = profile?.displayName.isNotEmpty == true
                ? profile!.displayName
                : fallbackName;
            final district = profile?.district ?? '';
            final taluk = profile?.taluk ?? '';
            final totalJobs = summary?.statistics.jobsPosted ?? profile?.totalJobs ?? 0;
            final rating = profile?.rating ?? 4.5;
            final photoUrl = profile?.photoUrl ?? '';

            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Header: Avatar + Info ──
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryPale,
                        border: Border.all(color: AppColors.primary.withAlpha(80), width: 2),
                      ),
                      child: photoUrl.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _avatarFallback(name),
                              ),
                            )
                          : _avatarFallback(name),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.sora(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textHead,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryPale,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'HIRER',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.greenPale,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.verified, size: 11, color: AppColors.green),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Verified Member',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (district.isNotEmpty || taluk.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              [taluk, district].where((s) => s.isNotEmpty).join(', '),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.textLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Reputation Stat Cards ──
                Row(
                  children: [
                    _statCard(
                      emoji: '⭐',
                      value: rating.toStringAsFixed(1),
                      label: 'Hirer Rating',
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      emoji: '📋',
                      value: '$totalJobs',
                      label: 'Jobs Posted',
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      emoji: '🤝',
                      value: '100%',
                      label: 'Direct Wage',
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Platform Trust Guarantee ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, color: AppColors.green, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Kelasagara Trust & Safety',
                            style: GoogleFonts.sora(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textHead,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _benefitRow(
                        Icons.check_circle_outline,
                        'Zero Platform Commission — 100% of agreed wage is paid directly to the worker.',
                      ),
                      const SizedBox(height: 6),
                      _benefitRow(
                        Icons.lock_outline,
                        'Two-Tier Privacy — Exact site address and contact numbers are only shared after acceptance.',
                      ),
                      const SizedBox(height: 6),
                      _benefitRow(
                        Icons.verified_user_outlined,
                        'Secure Arrival Verification — Work begins only after arrival OTP confirmation.',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Action Buttons ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            workerName: name,
                            jobTitle: 'Inquiry',
                            otherUserId: hirerId,
                            jobId: 'direct_$hirerId',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(
                      'Message Hirer',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _avatarFallback(String name) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'H';
    return Center(
      child: Text(
        letter,
        style: GoogleFonts.sora(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _statCard({required String emoji, required String value, required String label}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.sora(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.textHead,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppColors.textFaint,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _benefitRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.textBody,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
