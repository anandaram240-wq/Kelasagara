// lib/screens/jobs/job_detail_screen.dart
// Phase 5: Production Job Detail Screen for Kelasagara.
// Enforces Two-Tier Location Disclosure, Hirer Public Profile Inspection,
// Safe Application Submission with Pitch Notes, Real-Time Application State,
// and Direct Transition to Accepted Work Details.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../providers/jobs_provider.dart';
import '../../providers/auth_provider.dart';
import '../chat/chat_screen.dart';
import '../profile/hirer_profile_sheet.dart';
import 'work_detail_screen.dart';

class JobDetailScreen extends StatefulWidget {
  final Job job;
  const JobDetailScreen({super.key, required this.job});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  void _openApplySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ApplySheet(
        job: widget.job,
        onApplied: () {
          setState(() {});
        },
      ),
    );
  }

  Future<void> _withdrawApplication(String appId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Withdraw Application?', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(
          'Are you sure you want to withdraw your application for this job?',
          style: GoogleFonts.plusJakartaSans(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textMed)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Withdraw', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<JobsProvider>().withdrawApplication(appId, widget.job.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.textBody,
            content: Text('Application withdrawn.', style: GoogleFonts.plusJakartaSans()),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final cat = kJobCategories.firstWhere((c) => c.id == job.skill, orElse: () => kJobCategories.first);
    final auth = context.watch<AuthProvider>();
    final jobsProvider = context.watch<JobsProvider>();
    final myUid = auth.uid ?? '';

    // Watch application status for this specific job and worker
    return StreamBuilder<DocumentSnapshot>(
      stream: myUid.isNotEmpty
          ? FirebaseFirestore.instance.collection('applications').doc('app_${job.id}_$myUid').snapshots()
          : const Stream.empty(),
      builder: (ctx, snap) {
        Map<String, dynamic>? appData;
        String? appId;
        String? appStatus;

        if (snap.hasData && snap.data!.exists && snap.data!.data() != null) {
          appData = snap.data!.data() as Map<String, dynamic>;
          appId = snap.data!.id;
          appStatus = (appData['status'] as String? ?? 'pending').toLowerCase();
        }

        final isLocallyApplied = jobsProvider.appliedJobs.containsKey(job.id);
        final isWithdrawn = appStatus == 'withdrawn' || appStatus == 'cancelled';
        final isAccepted = appStatus == 'accepted';
        final isPending = !isWithdrawn && (appStatus == 'pending' || appStatus == 'applied' || isLocallyApplied);
        final bookingId = appData?['bookingId'] as String?;

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppColors.primary,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share_outlined, color: Colors.white),
                    // B09 FIX: Share job via clipboard copy
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      final title = widget.job.title;
                      final pay = widget.job.pay;
                      final text =
                          '🔨 $title — ₹$pay/day\nKelasagara ನಲ್ಲಿ ಅರ್ಜಿ ಹಾಕಿ / Apply on Kelasagara:\nhttps://kelasagara.in/jobs/${widget.job.id}';
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '🔗 ಲಿಂಕ್ ನಕಲಿಸಲಾಗಿದೆ / Link copied to clipboard',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            backgroundColor: AppColors.green,
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const SizedBox(height: 40),
                        Text(cat.emoji, style: const TextStyle(fontSize: 60)),
                        const SizedBox(height: 8),
                        Text(
                          job.title,
                          style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          job.urgent ? '🔴 URGENT HIRING' : '📋 Job Listing',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title & Compensation ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  job.title,
                                  style: GoogleFonts.sora(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textHead,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Posted by ${job.hirer}',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.verified, size: 12, color: AppColors.green),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${job.pay}',
                                style: GoogleFonts.sora(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                              ),
                              Text(
                                'per ${job.jobType == "Monthly Contract" ? "month" : "day"}',
                                style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Quick Info Grid ──
                      Row(
                        children: [
                          _infoBox('📍', 'Area', '${job.taluk.isNotEmpty ? "${job.taluk}, " : ""}${job.district}'),
                          const SizedBox(width: 8),
                          _infoBox('📋', 'Contract', job.jobType),
                          const SizedBox(width: 8),
                          _infoBox('🕒', 'Posted', job.ago.isNotEmpty ? job.ago : 'Recently'),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Accepted Banner ──
                      if (isAccepted) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.greenPale,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.green, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.celebration, color: AppColors.green, size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Application Accepted! 🎉',
                                    style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.green),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'The hirer has confirmed your booking. Exact site location and navigation directions are now unlocked.',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textBody, height: 1.4),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (bookingId != null && bookingId.isNotEmpty) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => WorkDetailScreen(bookingId: bookingId),
                                        ),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                    'View Confirmed Work & Directions →',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Pending Review Banner ──
                      if (isPending) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPale,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFFD5AA)),
                          ),
                          child: Row(
                            children: [
                              const Text('⏳', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Application Under Review',
                                      style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                                    ),
                                    Text(
                                      'You will receive a notification as soon as the hirer reviews.',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textBody),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (appId != null) _withdrawApplication(appId);
                                },
                                child: Text(
                                  'Withdraw',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.red, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Hirer Public Profile Preview Card ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.primaryPale,
                              child: Text(
                                job.hirer.isNotEmpty ? job.hirer[0].toUpperCase() : 'H',
                                style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    job.hirer,
                                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                                  ),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, size: 12, color: Color(0xFFF59E0B)),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${job.rating.toStringAsFixed(1)} Hirer Rating',
                                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () {
                                HirerPublicProfileSheet.show(context, hirerId: job.hirerId, fallbackName: job.hirer);
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primary),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              child: Text(
                                'Hirer Profile',
                                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Description ──
                      if (job.description.isNotEmpty) ...[
                        Text(
                          'Work Description',
                          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textHead),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            job.description,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textBody, height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Work Location (Two-Tier Location Gate) ──
                      Text(
                        'Work Site Area',
                        style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textHead),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 20, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    [job.village, job.taluk, job.district].where((s) => s.isNotEmpty).join(', '),
                                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Privacy Protection Notice
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.lock_outline, size: 14, color: AppColors.textLight),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      isAccepted
                                          ? 'Exact location and map directions are unlocked in your Confirmed Work Details.'
                                          : 'Exact site address and map navigation directions are securely locked and disclosed only after the hirer accepts your application.',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Fair Wage & Direct Payout Notice ──
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.greenPale,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield_outlined, color: AppColors.green, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Kelasagara Fair Marketplace: 100% of ₹${job.pay}/day is paid directly to you. Zero platform commission.',
                                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // B15 FIX: Report Job button
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _showReportSheet(context, job.id);
                          },
                          icon: const Icon(Icons.flag_outlined,
                              color: AppColors.textFaint, size: 16),
                          label: Text(
                            '🚩 ಕೆಲಸ ವರದಿ ಮಾಡಿ / Report this job',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12, color: AppColors.textFaint),
                          ),
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(top: BorderSide(color: AppColors.divider)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4))],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              workerName: job.hirer,
                              jobTitle: job.title,
                              otherUserId: job.hirerId,
                              jobId: job.id,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: Text('Chat', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: isAccepted
                          ? () {
                              if (bookingId != null && bookingId.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => WorkDetailScreen(bookingId: bookingId)),
                                );
                              }
                            }
                          : isPending
                              ? null
                              : () => _openApplySheet(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAccepted
                            ? AppColors.green
                            : isPending
                                ? const Color(0xFF059669)
                                : AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      child: Text(
                        isAccepted
                            ? 'View Work Details →'
                            : isPending
                                ? 'APPLIED ✓'
                                : 'APPLY NOW 🚀',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // B15: Report job bottom sheet
  void _showReportSheet(BuildContext context, String jobId) {
    String? selected;
    final reasons = [
      'ನಕಲಿ ಕೆಲಸ / Fake job posting',
      'ತಪ್ಪು ಮಾಹಿತಿ / Misleading information',
      'ಅನುಚಿತ ವಿಷಯ / Inappropriate content',
      'ವಂಚನೆ / Scam or fraud',
      'ಇತರೆ / Other',
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4))),
              ),
              const SizedBox(height: 20),
              Text('🚩 ಕೆಲಸ ವರದಿ ಮಾಡಿ / Report Job',
                  style: GoogleFonts.sora(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1E293B))),
              const SizedBox(height: 16),
              ...reasons.map((r) => GestureDetector(
                    onTap: () => setSheet(() => selected = r),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: selected == r
                            ? AppColors.primaryPale
                            : AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: selected == r
                                ? AppColors.primary
                                : AppColors.border),
                      ),
                      child: Row(children: [
                        Icon(
                            selected == r
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected == r
                                ? AppColors.primary
                                : AppColors.textFaint,
                            size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(r,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1E293B)))),
                      ]),
                    ),
                  )),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () async {
                        final uid = context.read<AuthProvider>().uid;
                        try {
                          await FirebaseFirestore.instance
                              .collection('reports')
                              .add({
                            'jobId': jobId,
                            'reportedBy': uid,
                            'reason': selected,
                            'reportedAt': FieldValue.serverTimestamp(),
                            'type': 'job',
                          });
                        } catch (e) {
                          debugPrint('Report error: $e');
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                '✅ ವರದಿ ಸಲ್ಲಿಸಲಾಗಿದೆ / Report submitted',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700)),
                            backgroundColor: AppColors.green,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.divider,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: Text('ವರದಿ ಮಾಡಿ / Submit Report',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBox(String emoji, String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 9, color: AppColors.textFaint, fontWeight: FontWeight.w600)),
            Text(
              value,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textHead),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Application Submission Sheet ──
class _ApplySheet extends StatefulWidget {
  final Job job;
  final VoidCallback onApplied;

  const _ApplySheet({required this.job, required this.onApplied});

  @override
  State<_ApplySheet> createState() => _ApplySheetState();
}

class _ApplySheetState extends State<_ApplySheet> {
  final _messageController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitApplication() async {
    final auth = context.read<AuthProvider>();
    if (auth.uid == null) return;

    setState(() => _isSubmitting = true);

    try {
      final user = auth.currentUser;
      final result = await context.read<JobsProvider>().applyToJob(
        jobId: widget.job.id,
        workerId: auth.uid!,
        workerName: auth.name,
        workerPhoto: user?.photoUrl ?? '',
        workerRating: user?.rating ?? 4.8,
        workerTotalJobs: user?.totalJobs ?? 0,
        workerSkills: user?.skills ?? [],
        workerVerified: user?.faceVerified ?? true,
        hirerId: widget.job.hirerId,
        hirerName: widget.job.hirer,
        jobTitle: widget.job.title,
        skill: widget.job.skill,
        pay: widget.job.pay,
        message: _messageController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        if (result != null) {
          widget.onApplied();
          showDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.black.withValues(alpha: 0.5),
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Lottie.asset(
                  'assets/lottie/success.json',
                  width: 160,
                  height: 160,
                  repeat: false,
                ),
                const SizedBox(height: 8),
                Text(
                  'Applied Successfully!',
                  style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'The hirer will review your application',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white70),
                ),
              ]),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 2500));
          if (mounted) Navigator.pop(context); // close dialog
        } else {
          final err = context.read<JobsProvider>().lastApplyError ?? 'Failed to submit application. Please try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.red,
              content: Text(err, style: GoogleFonts.plusJakartaSans()),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Apply for Job',
              style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            Text(
              widget.job.title,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 16),

            // Profile Snapshot Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryPale,
                    child: Text(
                      auth.name.isNotEmpty ? auth.name[0].toUpperCase() : 'W',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w900, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.name,
                          style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead),
                        ),
                        Text(
                          '⭐ ${(user?.rating ?? 4.8).toStringAsFixed(1)} • ${user?.totalJobs ?? 0} jobs completed',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${widget.job.pay}/day',
                    style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Pitch note input
            Text(
              'Message to Hirer (Optional)',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textHead),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _messageController,
              maxLines: 3,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead),
              decoration: InputDecoration(
                hintText: 'Introduce yourself, confirm your availability date, or highlight past experience with similar work...',
                hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textFaint),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 18),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitApplication,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSubmitting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text(
                            'APPLYING...',
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ],
                      )
                    : Text(
                        'Confirm & Submit Application 🚀',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
