import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/constants/job_categories.dart';
import '../providers/jobs_provider.dart';
import '../providers/auth_provider.dart';
import '../screens/jobs/job_detail_screen.dart';

// ── JobCard — Stateful for immediate apply feedback ──────────────────────────
class JobCard extends StatefulWidget {
  final Job job;
  final int index;
  final VoidCallback onApply;
  final bool alreadyApplied;
  const JobCard({
    super.key,
    required this.job,
    required this.index,
    required this.onApply,
    required this.alreadyApplied,
  });

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  bool _applying = false; // immediate UI feedback lock

  Color get _matchColor {
    if (widget.job.match >= 90) return const Color(0xFF059669);
    if (widget.job.match >= 75) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Future<void> _handleApply() async {
    if (_applying || widget.alreadyApplied) return;
    HapticFeedback.mediumImpact();

    // Immediate feedback — same frame as tap
    setState(() => _applying = true);

    try {
      final auth = context.read<AuthProvider>();
      final job = widget.job;
      final result = await context.read<JobsProvider>().applyToJob(
        jobId:      job.id,
        workerId:   auth.uid ?? '',
        workerName: auth.name,
        hirerId:    job.hirerId,
        jobTitle:   job.title,
        skill:      job.skill,
        hirerName:  job.hirer,
        pay:        job.pay,
      );
      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('✅ Application submitted to ${job.hirer.isNotEmpty ? job.hirer : "hirer"}!', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white)),
        ));
      } else {
        // Show error
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('Could not apply. Try again.', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white)),
        ));
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final cat = kJobCategories.firstWhere((c) => c.id == job.skill, orElse: () => kJobCategories.first);
    final applied = widget.alreadyApplied;

    return GestureDetector(
      onTap: () => Navigator.push(context, PageRouteBuilder(
        pageBuilder: (_, animation, __) => JobDetailScreen(job: job),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: animation, child: child),
        ),
        transitionDuration: const Duration(milliseconds: 280),
      )),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: job.urgent ? AppColors.red.withValues(alpha: 0.3) : AppColors.border,
            width: job.urgent ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2)),
            if (job.urgent) BoxShadow(color: AppColors.red.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(children: [
          // Urgent banner
          if (job.urgent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('🔴', style: TextStyle(fontSize: 10)),
                const SizedBox(width: 4),
                Text('URGENT HIRING', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.red, letterSpacing: 0.5)),
              ]),
            ),

          Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 8), child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: AppColors.primaryPale, borderRadius: BorderRadius.circular(14)), child: Center(child: Text(cat.emoji, style: const TextStyle(fontSize: 26)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(job.title, style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead))),
                if (job.verified) const Icon(Icons.verified, size: 14, color: Color(0xFF059669)),
              ]),
              Text(job.titleKn, style: GoogleFonts.notoSansKannada(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textLight)),
              Text(job.hirer, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint, fontWeight: FontWeight.w500)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${job.pay}', style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF059669))),
              Text('per ${job.jobType.contains("Month") ? "month" : "day"}', style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
            ]),
          ])),

          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: Row(children: [
            _chip('📍 ${job.taluk}'), const SizedBox(width: 6),
            _chip('${job.dist.toInt()}km'), const SizedBox(width: 6),
            _chip('⭐ ${job.rating.toStringAsFixed(1)}'), const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: _matchColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _matchColor.withValues(alpha: 0.25))),
              child: Text('${job.match.toInt()}% match', style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w800, color: _matchColor)),
            ),
          ])),

          Container(height: 1, color: AppColors.divider),
          Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12), child: Row(children: [
            Text('👥 ${job.applicants} applied • ${job.ago}', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint, fontWeight: FontWeight.w600)),
            const Spacer(),
            // Apply button — shows spinner immediately on tap, prevents double-tap
            if (applied)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: AppColors.greenPale, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFA7F3D0))),
                child: Text('APPLIED ✓', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
              )
            else
              GestureDetector(
                onTap: _handleApply,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: _applying
                      ? const LinearGradient(colors: [Color(0xFFE0E0E0), Color(0xFFE0E0E0)])
                      : const LinearGradient(colors: [AppColors.primary, AppColors.primaryFire]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _applying ? [] : [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: _applying
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        const SizedBox(width: 6),
                        Text('APPLYING...', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                      ])
                    : Text('APPLY NOW →', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
          ])),
        ]),
      ),
    );
  }

  Widget _chip(String l) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
    child: Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textMed)),
  );
}
