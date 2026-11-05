// lib/screens/profile/worker_profile_detail_screen.dart
// Premium full worker profile detail screen for Kelasagara.
// Complies with Sections 34-37 of the product specification.
// Displays truthful reputation, verified badges, skills taxonomy,
// declared service area (without exposing sensitive GPS coordinates),
// and canonical Message & Booking actions.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../models/user_profile.dart';
import '../../models/worker_search_result.dart';
import '../../providers/auth_provider.dart';
import '../../services/booking_service.dart';
import '../../services/chat_booking_service.dart';
import '../../services/worker_availability_service.dart';
import '../chat/chat_screen.dart';

class WorkerProfileDetailScreen extends StatefulWidget {
  final UserProfile worker;
  final WorkerSearchEntry? searchEntry;

  const WorkerProfileDetailScreen({
    super.key,
    required this.worker,
    this.searchEntry,
  });

  /// Convenient helper to fetch worker profile by UID and open the detail screen
  static Future<void> open(BuildContext context, String workerId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(workerId).get();
      if (!doc.exists || doc.data() == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Worker profile not found')),
          );
        }
        return;
      }
      final worker = UserProfile.fromMap(doc.id, doc.data()!);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorkerProfileDetailScreen(worker: worker)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading worker profile: $e')),
        );
      }
    }
  }

  @override
  State<WorkerProfileDetailScreen> createState() => _WorkerProfileDetailScreenState();
}

class _WorkerProfileDetailScreenState extends State<WorkerProfileDetailScreen> {
  bool _initiatingChat = false;
  bool _initiatingBooking = false;
  List<Map<String, dynamic>> _reviews = [];
  bool _loadingReviews = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('workerId', isEqualTo: widget.worker.uid)
          .where('status', isEqualTo: BookingStatus.completionVerified)
          .limit(5)
          .get();

      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data.containsKey('ratingData') || data.containsKey('stars')) {
          list.add(data);
        }
      }
      if (mounted) {
        setState(() {
          _reviews = list;
          _loadingReviews = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  Future<void> _onMessage() async {
    final auth = context.read<AuthProvider>();
    if (auth.uid == null) {
      _showToast('Please sign in to message this worker');
      return;
    }
    if (auth.uid == widget.worker.uid) {
      _showToast('You cannot message yourself');
      return;
    }

    setState(() => _initiatingChat = true);
    try {
      final workerSkill = widget.worker.skills.isNotEmpty
          ? widget.worker.skills.first
          : 'Service Inquiry';

      await ChatService.getOrCreate(
        myUid: auth.uid!,
        otherUid: widget.worker.uid,
        jobId: 'direct_${widget.worker.uid}',
        myName: auth.name,
        otherName: widget.worker.displayName,
        jobTitle: 'Direct Hire: $workerSkill',
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            workerName: widget.worker.displayName,
            jobTitle: 'Direct Hire: $workerSkill',
            otherUserId: widget.worker.uid,
            jobId: 'direct_${widget.worker.uid}',
          ),
        ),
      );
    } catch (e) {
      _showToast('Could not start conversation. Please try again.');
    } finally {
      if (mounted) setState(() => _initiatingChat = false);
    }
  }

  Future<void> _onBook() async {
    final auth = context.read<AuthProvider>();
    if (auth.uid == null) {
      _showToast('Please sign in to book this worker');
      return;
    }
    if (auth.uid == widget.worker.uid) {
      _showToast('You cannot book yourself');
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Request Booking',
          style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm booking request for ${widget.worker.displayName}?',
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _confirmRow('Daily Rate:', '₹${widget.worker.dailyRate}/day'),
                  const SizedBox(height: 6),
                  _confirmRow(
                    'Primary Skill:',
                    widget.worker.primarySkillId.isNotEmpty
                        ? widget.worker.primarySkillId
                        : 'General Work',
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Confirm',
              style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _initiatingBooking = true);
    try {
      final skillId = widget.worker.primarySkillId.isNotEmpty
          ? widget.worker.primarySkillId
          : 'general_work';

      final res = await BookingService.instance.createDirectBooking(
        hirerUid: auth.uid!,
        workerId: widget.worker.uid,
        skillId: skillId,
        idempotencyKey: '${auth.uid}_${widget.worker.uid}_${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
      );

      if (!mounted) return;
      if (res.success) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.green, size: 28),
                const SizedBox(width: 8),
                Text('Booking Created!', style: GoogleFonts.sora(fontWeight: FontWeight.w900)),
              ],
            ),
            content: Text(
              'Your direct booking request has been confirmed. The worker will be notified.',
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      } else {
        _showToast(res.errorMessage ?? 'Booking failed');
      }
    } catch (e) {
      _showToast('Booking failed. Please try again.');
    } finally {
      if (mounted) setState(() => _initiatingBooking = false);
    }
  }

  Widget _confirmRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textLight)),
        Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead)),
      ],
    );
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final worker = widget.worker;
    final skills = worker.skills
        .map((id) {
          try {
            return kJobCategories.firstWhere((c) => c.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<JobCategory>()
        .toList();

    final freshness = WorkerAvailabilityService.checkFreshness(worker.discoveryUpdatedAt);
    final isLive = worker.isAvailable && freshness != LocationFreshness.stale;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: AppColors.surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textHead),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: _buildAvatar(88),
                  ),
                ),
              ),
            ),
          ),

          // ── Profile Body ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + Handle + Availability
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker.displayName,
                              style: GoogleFonts.sora(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textHead,
                              ),
                            ),
                            Text(
                              '@${worker.userId}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppColors.textLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Availability Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isLive ? AppColors.greenPale : AppColors.surface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isLive ? AppColors.green : AppColors.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isLive ? AppColors.green : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isLive ? 'Available Now' : 'Currently Busy',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isLive ? AppColors.green : AppColors.textLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Verification Badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (worker.faceVerified)
                        _badge('✅ Identity Verified', AppColors.green),
                      if (worker.skillVerified)
                        _badge('🏆 Skill Certified', AppColors.violet),
                      if (worker.experienceDisplay.isNotEmpty)
                        _badge('⏱ ${worker.experienceDisplay}', AppColors.primary),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Stats Row
                  Row(
                    children: [
                      _statCard(
                        '⭐ Rating',
                        worker.totalRatings > 0
                            ? '${worker.rating.toStringAsFixed(1)} (${worker.totalRatings})'
                            : 'No reviews',
                        worker.totalRatings > 0 ? 'Verified' : 'New Worker',
                      ),
                      const SizedBox(width: 10),
                      _statCard('💼 Jobs', '${worker.totalJobs}', 'Completed'),
                      const SizedBox(width: 10),
                      _statCard('💰 Rate', '₹${worker.dailyRate}', 'Per Day'),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Distance / Matrix road ETA note (if from search entry)
                  if (widget.searchEntry != null) ...[
                    _buildDistanceCard(),
                    const SizedBox(height: 24),
                  ],

                  // About / Bio Section
                  _sectionTitle('About Worker'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      worker.bio.trim().isNotEmpty
                          ? worker.bio.trim()
                          : 'No detailed description provided by this worker.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: worker.bio.trim().isNotEmpty
                            ? AppColors.textBody
                            : AppColors.textLight,
                        height: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Skills Section
                  _sectionTitle('Skills & Expertise'),
                  const SizedBox(height: 8),
                  if (skills.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: skills.map((cat) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(cat.emoji, style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 8),
                              Text(
                                cat.label,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textHead,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    Text(
                      'No specific skills listed.',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textLight),
                    ),

                  const SizedBox(height: 24),

                  // Service Area (Strictly privacy compliant: no raw lat/lng)
                  _sectionTitle('Service Area & Coverage'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                [worker.village, worker.taluk, worker.district]
                                    .where((s) => s.isNotEmpty)
                                    .join(', '),
                                style: GoogleFonts.sora(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textHead,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.radar_outlined, color: AppColors.violet, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Service Radius: ${worker.serviceRadiusKm} km coverage area',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppColors.textLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '🔒 Exact real-time coordinates are kept private and never exposed publicly.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textFaint,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Customer Reviews Section
                  _sectionTitle('Verified Job Reviews'),
                  const SizedBox(height: 8),
                  if (_loadingReviews)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  else if (_reviews.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'No customer reviews yet. Be the first to hire and review!',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppColors.textLight,
                        ),
                      ),
                    )
                  else
                    ..._reviews.map((r) {
                      final stars = (r['stars'] ?? r['ratingData']?['qualityScore'] ?? 5.0) as num;
                      final comment = (r['ratingData']?['comments'] ?? r['comment'] ?? 'Work completed successfully').toString();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('⭐ ${stars.toStringAsFixed(1)}', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
                                const Spacer(),
                                Text('Verified Job', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.green, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(comment, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textBody)),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 90), // Space for sticky bottom bar
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Sticky Bottom Action Bar ───────────────────────────────────────────
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: _initiatingChat ? null : _onMessage,
                icon: _initiatingChat
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text(
                  'Message',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: _initiatingBooking ? null : _onBook,
                icon: _initiatingBooking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.white),
                label: Text(
                  'Book Worker',
                  style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.sora(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: AppColors.textHead,
      ),
    );
  }

  Widget _buildAvatar(double size) {
    final hasPhoto = widget.worker.photoUrl.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        gradient: hasPhoto ? null : const LinearGradient(
          colors: [Color(0xFFFC8019), Color(0xFFFFA44D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: hasPhoto
          ? ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: CachedNetworkImage(
                imageUrl: widget.worker.photoUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                memCacheWidth: (size * 2).toInt(),
                memCacheHeight: (size * 2).toInt(),
                errorWidget: (_, __, ___) => _avatarFallback(size),
                placeholder: (_, __) => _avatarFallback(size),
              ),
            )
          : _avatarFallback(size),
    );
  }

  Widget _avatarFallback(double size) {
    final letter = widget.worker.displayName.isNotEmpty
        ? widget.worker.displayName[0].toUpperCase()
        : '?';
    return Center(
      child: Text(
        letter,
        style: GoogleFonts.sora(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, String subtitle) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.sora(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.textHead,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                color: AppColors.textFaint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistanceCard() {
    final entry = widget.searchEntry!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.roadDistanceM != null)
                  Text(
                    '${(entry.roadDistanceM! / 1000).toStringAsFixed(1)} km by road • ${entry.etaNote}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  )
                else if (entry.geoDistanceKm != null)
                  Text(
                    '${entry.geoDistanceKm!.toStringAsFixed(1)} km straight-line distance',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                Text(
                  'Estimated travel distance from your search location',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
