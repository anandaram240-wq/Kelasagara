// ================================================================
// KELASAGARA — Assessment Result Screen
// Shown after worker submits assessment for review.
// Does NOT show score to worker — only shows submission status.
// Admin reviews in their own panel.
// ================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/skill_assessment.dart';

class AssessmentResultScreen extends StatelessWidget {
  final String assessmentId;
  final String skillName;
  final String emoji;

  const AssessmentResultScreen({
    super.key,
    required this.assessmentId,
    required this.skillName,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
              .collection('skillAssessments')
              .doc(assessmentId)
              .snapshots(),
            builder: (ctx, snap) {
              final assessment = snap.hasData && snap.data!.exists
                ? SkillAssessment.fromFirestore(snap.data!)
                : null;

              final status = assessment?.status ?? AssessmentStatus.submitted;
              final decision = assessment?.decision;

              // ── Approved ─────────────────────────────────────────
              if (status == AssessmentStatus.approved) {
                return _ResultView(
                  emoji: '🎉',
                  title: 'Skill Verified!',
                  titleKn: 'ಕೌಶಲ ಪರಿಶೀಲಿಸಲಾಗಿದೆ!',
                  message:
                    'Your $skillName practical skill has been reviewed and verified '
                    'by the Kelasagara team.',
                  messageKn:
                    'ನಿಮ್ಮ $skillName ಕೌಶಲವನ್ನು ಕೆಲಸಗಾರ ತಂಡ ಪರಿಶೀಲಿಸಿ ದೃಢಪಡಿಸಿದೆ.',
                  color: const Color(0xFF22C55E),
                  badgeLabel: 'Kelasagara Practical Skill Verified',
                  failureReasons: null,
                  actionLabel: 'View My Skill Passport',
                  onAction: () => Navigator.of(context)
                    ..pop()..pop()..pop(),
                );
              }

              // ── Rejected ──────────────────────────────────────────
              if (status == AssessmentStatus.rejected) {
                return _ResultView(
                  emoji: '📋',
                  title: 'Assessment Reviewed',
                  titleKn: 'ಮೌಲ್ಯಮಾಪನ ಪರಿಶೀಲಿಸಲಾಗಿದೆ',
                  message:
                    'Thank you for completing the assessment. '
                    'You can review the feedback and try again.',
                  messageKn:
                    'ಮೌಲ್ಯಮಾಪನ ಮಾಡಿದ್ದಕ್ಕೆ ಧನ್ಯವಾದ. '
                    'ನೀವು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಬಹುದು.',
                  color: const Color(0xFFF59E0B),
                  badgeLabel: null,
                  failureReasons: assessment?.failureReasons,
                  actionLabel: 'Back to Skill Passport',
                  onAction: () => Navigator.of(context)
                    ..pop()..pop()..pop(),
                );
              }

              // ── Submitted / Under Review (default) ───────────────
              return _ResultView(
                emoji: '⏳',
                title: 'Submitted!',
                titleKn: 'ಸಲ್ಲಿಸಲಾಗಿದೆ!',
                message:
                  'Your $emoji $skillName assessment has been submitted. '
                  'Our team will review your videos and update your '
                  'Skill Passport within 2–3 business days.',
                messageKn:
                  'ನಿಮ್ಮ $emoji $skillName ಮೌಲ್ಯಮಾಪನ ಸಲ್ಲಿಸಲಾಗಿದೆ. '
                  'ನಮ್ಮ ತಂಡ ನಿಮ್ಮ ವಿಡಿಯೊಗಳನ್ನು ಪರಿಶೀಲಿಸಿ 2–3 ದಿನಗಳಲ್ಲಿ '
                  'ನಿಮ್ಮ ಕೌಶಲ ಪಾಸ್‌ಪೋರ್ಟ್ ನವೀಕರಿಸುತ್ತಾರೆ.',
                color: const Color(0xFF3B82F6),
                badgeLabel: null,
                failureReasons: null,
                actionLabel: 'View My Skill Passport',
                onAction: () => Navigator.of(context)
                  ..pop()..pop()..pop(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final String emoji;
  final String title;
  final String titleKn;
  final String message;
  final String messageKn;
  final Color color;
  final String? badgeLabel;
  final List<String>? failureReasons;
  final String actionLabel;
  final VoidCallback onAction;

  const _ResultView({
    required this.emoji,
    required this.title,
    required this.titleKn,
    required this.message,
    required this.messageKn,
    required this.color,
    required this.badgeLabel,
    required this.failureReasons,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Text(emoji, style: const TextStyle(fontSize: 72))
            .animate()
            .scale(duration: 400.ms, curve: Curves.elasticOut),

          const SizedBox(height: 24),

          // Title
          Text(title,
            style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 26,
              fontWeight: FontWeight.bold))
            .animate().fadeIn(delay: 200.ms),

          Text(titleKn,
            style: GoogleFonts.notoSansKannada(
              color: Colors.white54, fontSize: 14))
            .animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 20),

          // Message
          Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: Colors.white70, fontSize: 14, height: 1.7))
            .animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 6),

          Text(messageKn,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKannada(
              color: Colors.white38, fontSize: 12, height: 1.7))
            .animate().fadeIn(delay: 500.ms),

          // Verified badge
          if (badgeLabel != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(badgeLabel!,
                    style: GoogleFonts.poppins(
                      color: color, fontWeight: FontWeight.w700,
                      fontSize: 12)),
                ],
              ),
            ).animate().fadeIn(delay: 600.ms),
          ],

          // Failure reasons
          if (failureReasons != null && failureReasons!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Feedback from reviewer:',
                    style: GoogleFonts.poppins(
                      color: Colors.white54, fontSize: 11,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...failureReasons!.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: Colors.white38)),
                        Expanded(
                          child: Text(r,
                            style: GoogleFonts.poppins(
                              color: Colors.white60, fontSize: 12))),
                      ],
                    ))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 40),

          // Action button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
              child: Text(actionLabel,
                style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w700,
                  fontSize: 14))))
            .animate().fadeIn(delay: 700.ms),
        ],
      ),
    );
  }
}
