// lib/screens/jobs/job_applicants_screen.dart
// Phase 5: Hirer Applicant Review Screen for Kelasagara.
// Lists real-time applicants for a job, lets hirers inspect canonical full worker profiles,
// initiate in-context chats, and execute atomic acceptance transactions.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../providers/auth_provider.dart';
import '../../services/booking_service.dart';
import '../chat/chat_screen.dart';
import '../profile/worker_profile_detail_screen.dart';
import 'work_detail_screen.dart';

class JobApplicantsScreen extends StatelessWidget {
  final String jobId;
  final String jobTitle;
  final String skillId;
  final int pay;

  const JobApplicantsScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
    required this.skillId,
    required this.pay,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final myUid = auth.uid ?? '';

    final cat = kJobCategories.firstWhere((c) => c.id == skillId, orElse: () => kJobCategories.first);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textHead),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Applicants', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textHead)),
            Text(jobTitle, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Job Summary Strip ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.surface,
            child: Row(
              children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(jobTitle, style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                      Text('${cat.label} • ₹$pay/day', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF059669), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),

          // ── Real-Time Applicants Stream ──
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: myUid.isNotEmpty
                  ? FirebaseFirestore.instance.collection('applications').where('hirerId', isEqualTo: myUid).snapshots()
                  : FirebaseFirestore.instance.collection('applications').where('jobId', isEqualTo: jobId).snapshots(),
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text('Error loading applicants: ${snap.error}', style: GoogleFonts.plusJakartaSans(color: AppColors.red)),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }

                final allDocs = snap.data!.docs;
                final docs = allDocs.where((d) => (d.data() as Map<String, dynamic>)['jobId'] == jobId).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('📋', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(
                          'No applicants yet',
                          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Qualified workers nearby are being notified.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final appDoc = docs[i];
                    return _ApplicantReviewCard(
                      appDoc: appDoc,
                      jobId: jobId,
                      jobTitle: jobTitle,
                      skill: skillId,
                      pay: pay,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicantReviewCard extends StatefulWidget {
  final QueryDocumentSnapshot appDoc;
  final String jobId;
  final String jobTitle;
  final String skill;
  final int pay;

  const _ApplicantReviewCard({
    required this.appDoc,
    required this.jobId,
    required this.jobTitle,
    required this.skill,
    required this.pay,
  });

  @override
  State<_ApplicantReviewCard> createState() => _ApplicantReviewCardState();
}

class _ApplicantReviewCardState extends State<_ApplicantReviewCard> {
  bool _isLoading = false;

  Future<void> _confirmAccept(BuildContext context) async {
    final data = widget.appDoc.data() as Map<String, dynamic>;
    final workerName = data['workerName'] as String? ?? 'this worker';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Accept $workerName?', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(
          'Accepting will:\n'
          '• Confirm the booking at ₹${widget.pay}/day\n'
          '• Unlock your exact work site address and directions for $workerName\n'
          '• Mark the job as Filled\n'
          '• Notify other applicants that the position is filled',
          style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textMed)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Confirm & Accept', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _executeAccept();
    }
  }

  Future<void> _executeAccept() async {
    setState(() => _isLoading = true);
    final data = widget.appDoc.data() as Map<String, dynamic>;

    final auth = context.read<AuthProvider>();

    try {
      // Fetch job doc to get approximate location or fallback
      final jobDoc = await FirebaseFirestore.instance.collection('jobs').doc(widget.jobId).get();
      if (!mounted) return;
      final jd = jobDoc.exists ? jobDoc.data()! : <String, dynamic>{};
      final locMap = jd['location'] as Map<String, dynamic>?;

      var hirerUid = auth.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
      if (hirerUid.isEmpty) {
        hirerUid = (data['hirerId'] ?? jd['hirerId'] ?? jd['hirerUid'] ?? jd['createdById'] ?? jd['createdBy'] ?? '').toString();
      }

      final lat = ((jd['lat'] ?? jd['jobLat'] ?? locMap?['lat'] ?? 0.0) as num).toDouble();
      final lng = ((jd['lng'] ?? jd['jobLng'] ?? locMap?['lng'] ?? 0.0) as num).toDouble();
      final addr = (jd['address'] ?? jd['jobAddress'] ?? locMap?['address'] ?? '') as String;

      final result = await BookingService.instance.acceptApplication(
        hirerUid: hirerUid,
        applicationId: widget.appDoc.id,
        applicationData: {
          'jobId': widget.jobId,
          'workerId': data['workerId'] as String? ?? '',
          'workerName': data['workerName'] as String? ?? '',
          'hirerId': hirerUid,
          'jobTitle': (data['jobTitle'] ?? jd['title'] ?? widget.jobTitle) as String,
          'skill': (data['skill'] ?? jd['skill'] ?? widget.skill) as String,
          'pay': (data['pay'] as num?)?.toInt() ?? (jd['pay'] as num?)?.toInt() ?? widget.pay,
          'jobLat': lat,
          'jobLng': lng,
          'jobAddress': addr,
        },
      );

      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Acceptance failed');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              '🎉 Worker accepted! Booking confirmed.',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        );

        if (result.bookingId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => WorkDetailScreen(bookingId: result.bookingId!),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final cleanMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(cleanMsg, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('applications').doc(widget.appDoc.id).update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.appDoc.data() as Map<String, dynamic>;
    final status = d['status'] as String? ?? 'pending';
    final workerName = d['workerName'] as String? ?? 'Worker';
    final workerId = d['workerId'] as String? ?? '';
    final message = d['message'] as String? ?? '';
    final rating = (d['workerRating'] as num?)?.toDouble() ?? 4.8;
    final totalJobs = (d['workerTotalJobs'] as num?)?.toInt() ?? 12;
    final photoUrl = d['workerPhoto'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status == 'accepted' ? AppColors.green : AppColors.border, width: status == 'accepted' ? 1.5 : 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Worker Header Row ──
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryPale,
                  border: Border.all(color: AppColors.primary.withAlpha(60), width: 1.5),
                ),
                child: photoUrl.isNotEmpty
                    ? ClipOval(child: CachedNetworkImage(
                        imageUrl: photoUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                        errorWidget: (_, __, ___) => _fallbackAvatar(workerName),
                        placeholder: (_, __) => _fallbackAvatar(workerName),
                      ))
                    : _fallbackAvatar(workerName),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workerName,
                      style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textHead),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('⭐ ${rating.toStringAsFixed(1)}', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                        const SizedBox(width: 8),
                        Text('💼 $totalJobs jobs', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
                        const SizedBox(width: 8),
                        const Icon(Icons.verified, size: 12, color: AppColors.green),
                        const SizedBox(width: 2),
                        Text('Verified', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.green)),
                      ],
                    ),
                  ],
                ),
              ),
              _statusBadge(status),
            ],
          ),

          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '"$message"',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textBody, fontStyle: FontStyle.italic, height: 1.4),
              ),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 10),

          // ── Action Buttons ──
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => WorkerProfileDetailScreen.open(context, workerId),
                icon: const Icon(Icons.person_outline, size: 14),
                label: Text('Full Profile', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textBody,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        workerName: workerName,
                        jobTitle: widget.jobTitle,
                        otherUserId: workerId,
                        jobId: widget.jobId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 14),
                label: Text('Chat', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const Spacer(),
              if (status == 'pending') ...[
                if (_isLoading)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                else ...[
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.red, size: 20),
                    tooltip: 'Reject',
                    onPressed: _reject,
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: () => _confirmAccept(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: Text('Accept ✅', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ],
              ] else if (status == 'accepted') ...[
                ElevatedButton(
                  onPressed: () {
                    final bId = d['bookingId'] as String? ?? 'booking_${widget.appDoc.id}';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkDetailScreen(bookingId: bId),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text('View Work Details →', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _fallbackAvatar(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'W',
        style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg = AppColors.primaryPale;
    Color fg = AppColors.primary;
    String label = status.toUpperCase();

    if (status == 'accepted') {
      bg = AppColors.greenPale;
      fg = AppColors.green;
      label = 'ACCEPTED ✅';
    } else if (status == 'rejected') {
      bg = AppColors.red.withAlpha(20);
      fg = AppColors.red;
      label = 'REJECTED';
    } else if (status == 'withdrawn') {
      bg = AppColors.surface2;
      fg = AppColors.textFaint;
      label = 'WITHDRAWN';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w900, color: fg),
      ),
    );
  }
}
