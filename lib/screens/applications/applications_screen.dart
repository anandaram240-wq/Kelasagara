import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../providers/auth_provider.dart';
import '../../providers/jobs_provider.dart';
import '../../services/booking_service.dart';
import '../tracking/journey_navigator.dart';
import '../chat/chat_screen.dart';
import '../jobs/work_detail_screen.dart';
import '../tracking/work_completion_screen.dart';

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});
  @override State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tab;
  @override void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); }
  @override void dispose() { _tab.dispose(); super.dispose(); }
  @override bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final auth = context.watch<AuthProvider>();
    final uid = auth.uid ?? '';
    final isWorker = auth.isWorker;

    if (uid.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(isWorker ? 'My Applications' : 'Applicants', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textHead)),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textFaint,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 12),
          tabs: isWorker
            ? [
                const Tab(text: 'Applications'),
                const Tab(text: 'My Bookings'),
              ]
            : [
                const Tab(text: 'Applications'),
                const Tab(text: 'Bookings'),
              ],
        ),
      ),
      body: TabBarView(controller: _tab, children: [
        _ApplicationsList(uid: uid, isWorker: isWorker),
        _BookingsList(uid: uid, isWorker: isWorker),
      ]),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Applications List
// ────────────────────────────────────────────────────────────────────────────
class _ApplicationsList extends StatelessWidget {
  final String uid;
  final bool isWorker;
  const _ApplicationsList({required this.uid, required this.isWorker});

  @override
  Widget build(BuildContext context) {
    // ── FIX BUG #2: Remove .where('status') + .orderBy() to avoid composite index ──
    // Worker: all their applications
    // Hirer: all applications for jobs where hirerId == uid (NO status filter in query)
    // Sort locally in Flutter after receiving docs.
    final query = isWorker
      ? FirebaseFirestore.instance
          .collection('applications')
          .where('workerId', isEqualTo: uid)
          // No orderBy here — sort locally
      : FirebaseFirestore.instance
          .collection('applications')
          .where('hirerId', isEqualTo: uid);
          // No status filter here — filter locally. No orderBy — sort locally.

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return _EmptyState(msg: 'Error loading applications.\n${snap.error}', emoji: '⚠️');
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

        // Sort locally by appliedAt descending
        final docs = [...snap.data!.docs];
        docs.sort((a, b) {
          final aT = (a.data() as Map)['appliedAt'] as Timestamp?;
          final bT = (b.data() as Map)['appliedAt'] as Timestamp?;
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return bT.compareTo(aT);
        });

        if (docs.isEmpty) return _EmptyState(msg: isWorker ? 'No applications yet\nApply to jobs to see them here' : 'No applicants yet', emoji: '📋');

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status'] as String? ?? 'pending';
            final Color statusColor = status == 'accepted' ? AppColors.green
                : status == 'rejected' ? AppColors.red
                : status == 'withdrawn' ? AppColors.textFaint
                : const Color(0xFFF59E0B);
            return RepaintBoundary(
              child: _AppCard(
                docId: docs[i].id,
                data: d,
                status: status,
                statusColor: statusColor,
                isWorker: isWorker,
                index: i,
              ),
            );
          },
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Application Card (stateful for accept/reject actions)
// ────────────────────────────────────────────────────────────────────────────
class _AppCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final String status;
  final Color statusColor;
  final bool isWorker;
  final int index;
  const _AppCard({required this.docId, required this.data, required this.status, required this.statusColor, required this.isWorker, required this.index});

  @override State<_AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<_AppCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: AppColors.primaryPale, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(
              // Derive emoji from category ID — 'skillEmoji' field was never written
              kJobCategories.firstWhere((c) => c.id == (d['skill'] ?? ''), orElse: () => kJobCategories.first).emoji,
              style: const TextStyle(fontSize: 22),
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['jobTitle'] ?? 'Job', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead)),
            Text(widget.isWorker ? (d['hirerName'] ?? '') : (d['workerName'] ?? ''), style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
            Text('₹${d['pay'] ?? 0}/day', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.green)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  _statusTimeline(widget.status),
                  const SizedBox(width: 8),
                  Text(
                    _statusLabel(widget.status),
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight),
                  ),
                ],
              ),
            ),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: widget.statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: widget.statusColor.withValues(alpha: 0.3))), child: Text(widget.status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w900, color: widget.statusColor))),
        ])),
        if ((d['message'] as String? ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10)), child: Text(d['message'], style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textBody)))),
        Container(height: 1, color: AppColors.divider),
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: Row(children: [
          // Chat button — always available
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
              workerName: widget.isWorker ? d['hirerName'] ?? 'Hirer' : d['workerName'] ?? 'Worker',
              jobTitle: d['jobTitle'] ?? 'Chat',
              otherUserId: widget.isWorker ? d['hirerId'] ?? '' : d['workerId'] ?? '',
              jobId: d['jobId'] ?? widget.docId,
            ))),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)), child: Row(children: [const Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.primary), const SizedBox(width: 4), Text('Chat', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary))])),
          ),
          const Spacer(),
          if (!widget.isWorker && widget.status == 'pending') ...[ // Hirer: Accept / Reject
            _loading
              ? const SizedBox(width: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
              : Row(children: [
                  GestureDetector(onTap: () => _accept(context), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: AppColors.greenPale, borderRadius: BorderRadius.circular(10)), child: Text('✅ Accept', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.green)))),
                  const SizedBox(width: 6),
                  GestureDetector(onTap: () => _reject(context), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: AppColors.redPale, borderRadius: BorderRadius.circular(10)), child: Text('❌ Reject', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.red)))),
                ]),
          ],
          if (widget.isWorker && widget.status == 'pending') ...[ // Worker: Withdraw
            _loading
              ? const SizedBox(width: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
              : GestureDetector(onTap: () => _withdraw(context), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: AppColors.redPale, borderRadius: BorderRadius.circular(10)), child: Text('Withdraw', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.red)))),
          ],
          if (widget.status == 'accepted') ...[
            GestureDetector(
              onTap: () {
                final bId = d['bookingId'] as String? ?? 'booking_${widget.docId}';
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => WorkDetailScreen(bookingId: bId)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: AppColors.greenPale, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.assignment_outlined, size: 14, color: AppColors.green),
                  const SizedBox(width: 4),
                  Text('Work Details',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.green)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () async {
                final bId = d['bookingId'] as String? ?? 'booking_${widget.docId}';
                try {
                  final snap = await FirebaseFirestore.instance
                      .collection('bookings').doc(bId).get();
                  if (!snap.exists) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Booking not found — ask hirer to accept first.'),
                        backgroundColor: Colors.red));
                    }
                    return;
                  }
                  final bd = snap.data()!;
                  final bm = {...bd, 'bookingId': snap.id};
                  if (context.mounted) {
                    if (widget.isWorker) {
                      await JourneyNavigator.openWorker(context,
                          booking: bm, workerId: bd['workerId'] ?? '');
                    } else {
                      await JourneyNavigator.openHirer(context, booking: bm);
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: AppColors.primaryPale, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.navigation, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(widget.isWorker ? '📍 Journey' : '🗺️ Track',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ]),
              ),
            ),
            if (!widget.isWorker) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () async {
                  final bId = d['bookingId'] as String? ?? 'booking_${widget.docId}';
                  try {
                    final snap = await FirebaseFirestore.instance.collection('bookings').doc(bId).get();
                    if (!snap.exists) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Booking details not found.'), backgroundColor: Colors.red));
                      }
                      return;
                    }
                    final bd = snap.data()!;
                    final bStatus = bd['status'] as String? ?? '';
                    if (context.mounted) {
                      if (bStatus == 'working' || bStatus == 'completion_requested') {
                        final auth = context.read<AuthProvider>();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkCompletionScreen(
                              bookingId: bId,
                              workerId: bd['workerId'] ?? '',
                              hirerId: auth.uid ?? bd['hirerId'] ?? '',
                              jobId: bd['jobId'] ?? '',
                              skillId: bd['skillId'] ?? 'general',
                              workerName: bd['workerName'] ?? '',
                              jobTitle: bd['jobTitle'] ?? '',
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => WorkDetailScreen(bookingId: bId)));
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text('Rate',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFD97706))),
                  ]),
                ),
              ),
            ],
          ],
        ])),
      ]),
    ).animate(delay: Duration(milliseconds: widget.index * 60)).slideY(begin: 0.1, duration: 300.ms).fadeIn();
  }

  static Widget _statusTimeline(String status) {
    final steps = ['pending', 'seen', 'shortlisted', 'accepted'];
    final labels = ['Applied', 'Seen', 'Shortlisted', 'Hired'];
    final currentIndex = steps.indexOf(status.toLowerCase());
    final effectiveIndex = currentIndex < 0 ? 0 : currentIndex;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final filled = (i ~/ 2) < effectiveIndex;
          return Container(
            width: 18, height: 2,
            color: filled ? AppColors.green : AppColors.border,
          );
        } else {
          final idx = i ~/ 2;
          final done = idx <= effectiveIndex;
          return Tooltip(
            message: labels[idx],
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: done ? AppColors.green : AppColors.border,
                shape: BoxShape.circle,
              ),
            ),
          );
        }
      }),
    );
  }

  static String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return 'Applied';
      case 'seen': return 'Seen by hirer';
      case 'shortlisted': return 'Shortlisted!';
      case 'accepted': return 'Hired ✓';
      case 'rejected': return 'Not selected';
      default: return status;
    }
  }

  // ── FIX BUG #3: Proper acceptance using BookingService ───────────────────
  Future<void> _accept(BuildContext ctx) async {
    setState(() => _loading = true);
    final d = widget.data;
    try {
      final auth = ctx.read<AuthProvider>();
      final hirerUid = auth.uid ?? (d['hirerId'] as String? ?? '');

      // Get job data to fetch location
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(d['jobId']).get();
      final jobData = jobDoc.exists ? jobDoc.data()! : <String, dynamic>{};

      final result = await BookingService.instance.acceptApplication(
        hirerUid: hirerUid,
        applicationId: widget.docId,
        applicationData: {
          'jobId':         d['jobId'] ?? '',
          'workerId':      d['workerId'] ?? '',
          'workerName':    d['workerName'] ?? '',
          'hirerId':       hirerUid,
          'jobTitle':      d['jobTitle'] ?? '',
          'skill':         d['skill'] ?? '',
          'pay':           (d['pay'] as num?)?.toInt() ?? 0,
          'jobLat':        (jobData['lat'] as num?)?.toDouble() ?? 0.0,
          'jobLng':        (jobData['lng'] as num?)?.toDouble() ?? 0.0,
          'jobAddress':    (jobData['location'] as Map<String,dynamic>?)?['address'] as String? ?? '',
        },
      );

      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Acceptance failed');
      }

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('🎉 Worker accepted! Booking confirmed.', style: GoogleFonts.sora(fontWeight: FontWeight.w700)),
        ));

        if (result.bookingId != null) {
          Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => WorkDetailScreen(bookingId: result.bookingId!),
            ),
          );
        }
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          backgroundColor: AppColors.red,
          content: Text('Error: $e', style: GoogleFonts.plusJakartaSans()),
        ));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reject(BuildContext ctx) async {
    await FirebaseFirestore.instance.collection('applications').doc(widget.docId).update({
      'status': 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _withdraw(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Withdraw Application?', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(
          'Are you sure you want to withdraw this application? You can reapply later.',
          style: GoogleFonts.plusJakartaSans(fontSize: 12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Withdraw', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final jobId = widget.data['jobId'] as String? ?? '';
      await ctx.read<JobsProvider>().withdrawApplication(widget.docId, jobId);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.textBody,
            content: Text('Application withdrawn.', style: GoogleFonts.plusJakartaSans()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Bookings List
// ────────────────────────────────────────────────────────────────────────────
class _BookingsList extends StatelessWidget {
  final String uid;
  final bool isWorker;
  const _BookingsList({required this.uid, required this.isWorker});

  @override
  Widget build(BuildContext context) {
    final field = isWorker ? 'workerId' : 'hirerId';
    // ── FIX BUG #5: Remove .orderBy() to avoid composite index requirement ──
    // Sort locally instead.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where(field, isEqualTo: uid)
          // No orderBy — avoid composite index error
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return _EmptyState(msg: 'Error loading bookings.\n${snap.error}', emoji: '⚠️');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

        // Sort locally by createdAt descending
        final docs = [...snap.data!.docs];
        docs.sort((a, b) {
          final aT = (a.data() as Map)['createdAt'] as Timestamp?;
          final bT = (b.data() as Map)['createdAt'] as Timestamp?;
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return bT.compareTo(aT);
        });

        if (docs.isEmpty) return const _EmptyState(msg: 'No bookings yet', emoji: '📦');

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status'] as String? ?? 'confirmed';
            final statusColors = {
              'confirmed': const Color(0xFFF59E0B),
              'tracking':  AppColors.primary,
              'arrived':   AppColors.violet,
              'working':   AppColors.green,
              'completed': AppColors.textFaint,
            };
            final color = statusColors[status] ?? AppColors.primary;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
              child: Column(children: [
                Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['jobTitle'] ?? 'Booking', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                    Text(isWorker ? (d['hirerName'] ?? '') : (d['workerName'] ?? ''), style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
                    Text('₹${d['pay'] ?? 0}/day', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.green)),
                  ]),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Text(status.toUpperCase().replaceAll('_', ' '), style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w900, color: color))),
                    const SizedBox(height: 4),
                    Text('ID: ${docs[i].id}', style: GoogleFonts.plusJakartaSans(fontSize: 9, color: AppColors.textFaint)),
                  ]),
                ])),
                Container(height: 1, color: AppColors.divider),
                Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: Row(children: [
                  // ── TRACK LIVE: opens real GPS journey screen ────────────
                  GestureDetector(
                    onTap: () {
                      final bm = {...d, 'bookingId': docs[i].id};
                      if (isWorker) {
                        JourneyNavigator.openWorker(ctx,
                            booking: bm, workerId: uid);
                      } else {
                        JourneyNavigator.openHirer(ctx, booking: bm);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: AppColors.primaryPale,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primaryBorder)),
                      child: Row(children: [
                        const Icon(Icons.navigation, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(isWorker ? '🚶 Journey' : '🗺️ Track Live',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ChatScreen(workerName: isWorker ? d['hirerName'] ?? 'Hirer' : d['workerName'] ?? 'Worker', jobTitle: d['jobTitle'] ?? 'Chat', otherUserId: isWorker ? d['hirerId'] ?? '' : d['workerId'] ?? '', jobId: d['jobId'] ?? docs[i].id))),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)), child: Row(children: [const Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.textMed), const SizedBox(width: 4), Text('Chat', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMed))])),
                  ),
                ])),

              ]),
            ).animate(delay: Duration(milliseconds: i * 60)).slideY(begin: 0.1, duration: 300.ms).fadeIn();
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String emoji, msg;
  const _EmptyState({required this.emoji, required this.msg});
  @override
  Widget build(BuildContext context) =>
    Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 110, height: 110,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryPale, AppColors.violetPale],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 48))),
        ),
        const SizedBox(height: 20),
        Text(msg, textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textLight, height: 1.5)),
      ]),
    ));
}
