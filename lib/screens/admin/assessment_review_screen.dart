// ================================================================
// KELASAGARA — Admin Assessment Review Screen
// Admin sees submitted assessments with evidence videos.
// Safety gate enforced: cannot approve if safetyScore < threshold.
// Rubric scoring per occupation standard.
// ================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/skill_assessment.dart';
import '../../services/assessment_service.dart';
import '../../core/constants/job_categories.dart';

class AssessmentReviewScreen extends StatelessWidget {
  const AssessmentReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Assessment Reviews',
          style: GoogleFonts.poppins(
            color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: StreamBuilder<List<SkillAssessment>>(
        stream: AssessmentService.instance.streamPendingReviews(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF3B82F6)));
          }

          final assessments = snap.data ?? [];
          if (assessments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('✅', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  Text('No assessments pending review',
                    style: GoogleFonts.poppins(
                      color: Colors.white54, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: assessments.length,
            itemBuilder: (ctx, i) =>
              _AssessmentReviewCard(assessment: assessments[i])
                .animate().fadeIn(delay: (i * 80).ms),
          );
        },
      ),
    );
  }
}

// ── Assessment review card ─────────────────────────────────────────
class _AssessmentReviewCard extends StatefulWidget {
  final SkillAssessment assessment;
  const _AssessmentReviewCard({required this.assessment});
  @override State<_AssessmentReviewCard> createState() => _AssessmentReviewCardState();
}

class _AssessmentReviewCardState extends State<_AssessmentReviewCard> {
  bool _expanded = false;
  bool _submitting = false;

  final Map<String, int> _rubricScores = {};
  final List<String> _failureReasons = [];
  final _notesCtrl = TextEditingController();

  static const _rubricItems = [
    ('safety',       'Safety Compliance'),
    ('technique',    'Technique & Skill'),
    ('tools',        'Tool Handling'),
    ('quality',      'Work Quality'),
    ('efficiency',   'Efficiency'),
  ];

  @override
  void initState() {
    super.initState();
    // Initialize rubric with 0 scores
    for (final item in _rubricItems) {
      _rubricScores[item.$1] = 0;
    }
  }

  @override
  void dispose() { _notesCtrl.dispose(); super.dispose(); }

  bool get _safetyGatePassed {
    final category = kGetCategory(widget.assessment.skillId);
    final threshold = category?.safetyThreshold ?? 4;
    return (_rubricScores['safety'] ?? 0) >= threshold;
  }

  bool get _canApprove => _rubricScores.values.every((v) => v > 0) && _safetyGatePassed;

  Future<void> _submitDecision(String decision) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await AssessmentService.instance.submitAssessorDecision(
        assessmentId:   widget.assessment.id,
        decision:       decision,
        rubricScores:   Map.from(_rubricScores),
        failureReasons: List.from(_failureReasons),
        assessorNotes:  _notesCtrl.text.trim().isEmpty
                          ? null : _notesCtrl.text.trim(),
      );
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assessment;
    final category = kGetCategory(a.skillId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155))),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(category?.emoji ?? '🔧',
                    style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category?.label ?? a.skillId,
                          style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 15,
                            fontWeight: FontWeight.bold)),
                        Text('Attempt #${a.attemptNumber} · '
                          '${a.evidenceIds.length} video(s)',
                          style: GoogleFonts.poppins(
                            color: Colors.white54, fontSize: 11)),
                        if (a.knowledgeScore != null)
                          Text('Knowledge: ${a.knowledgeScore!.round()}%',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF3B82F6), fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withAlpha(25),
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      a.status == AssessmentStatus.underReview
                        ? 'Under Review' : 'Submitted',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFF59E0B),
                        fontSize: 10, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54),
                ],
              ),
            ),
          ),

          // ── Expanded review panel ──────────────────────────────────
          if (_expanded) ...[
            const Divider(color: Color(0xFF334155), height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Evidence videos
                  if (a.evidenceIds.isNotEmpty) ...[
                    _SectionLabel('📹 Evidence Videos'),
                    ...a.evidenceIds.map((id) => _EvidenceVideoTile(
                      evidenceId: id, assessmentId: a.id)),
                    const SizedBox(height: 16),
                  ],

                  // Rubric scoring
                  _SectionLabel('📊 Rubric Scoring (1–5)'),
                  const SizedBox(height: 8),

                  // Safety gate warning
                  if (!_safetyGatePassed && (_rubricScores['safety'] ?? 0) > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withAlpha(80))),
                      child: Row(children: [
                        const Icon(Icons.warning_rounded,
                          color: Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚡ Safety score ${_rubricScores['safety']}/5 is below required '
                            '${category?.safetyThreshold ?? 4}/5 threshold. '
                            'Cannot approve.',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFEF4444), fontSize: 11))),
                      ]),
                    ),

                  // Rubric sliders
                  ..._rubricItems.map((item) => _RubricRow(
                    label:    item.$2,
                    rubricKey: item.$1,
                    value:    _rubricScores[item.$1] ?? 0,
                    isSafety: item.$1 == 'safety',
                    safetyThreshold: category?.safetyThreshold ?? 4,
                    onChanged: (v) => setState(() => _rubricScores[item.$1] = v),
                  )),

                  const SizedBox(height: 16),

                  // Failure reasons (optional)
                  _SectionLabel('📝 Feedback / Failure Reasons'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Optional notes for the worker...',
                      hintStyle: GoogleFonts.poppins(
                        color: Colors.white38, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF334155))),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF334155))),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF3B82F6))))),

                  const SizedBox(height: 20),

                  // Decision buttons
                  if (_submitting)
                    const Center(child: CircularProgressIndicator(
                      color: Color(0xFF3B82F6)))
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _submitDecision('fail'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFEF4444)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                            child: Text('Not Passed',
                              style: GoogleFonts.poppins(
                                color: const Color(0xFFEF4444),
                                fontWeight: FontWeight.w700)))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _canApprove
                              ? () => _submitDecision('pass')
                              : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              disabledBackgroundColor: const Color(0xFF334155),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                            child: Text(
                              _canApprove ? 'Approve ✓' : 'Score all first',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Evidence video tile ────────────────────────────────────────────
class _EvidenceVideoTile extends StatefulWidget {
  final String evidenceId;
  final String assessmentId;
  const _EvidenceVideoTile({required this.evidenceId, required this.assessmentId});
  @override State<_EvidenceVideoTile> createState() => _EvidenceVideoTileState();
}

class _EvidenceVideoTileState extends State<_EvidenceVideoTile> {
  String? _playbackUrl;
  bool _loading = false;

  Future<void> _loadUrl() async {
    setState(() => _loading = true);
    try {
      // Get evidence storageKey from Firestore
      final doc = await FirebaseFirestore.instance
        .collection('assessmentEvidence')
        .doc(widget.evidenceId)
        .get();

      final storageKey = doc.data()?['storageKey'] as String?;
      if (storageKey == null) {
        setState(() { _loading = false; });
        return;
      }

      final url = await FirebaseStorage.instance
        .ref(storageKey)
        .getDownloadURL();

      setState(() { _playbackUrl = url; _loading = false; });

      // Open in browser/system video player
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155))),
      child: Row(
        children: [
          const Icon(Icons.videocam_rounded,
            color: Color(0xFF3B82F6), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Evidence: ${widget.evidenceId.substring(0, 8)}...',
              style: GoogleFonts.poppins(
                color: Colors.white60, fontSize: 11))),
          if (_loading)
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF3B82F6)))
          else
            TextButton(
              onPressed: _loadUrl,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: Text('▶ Play',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF3B82F6),
                  fontSize: 12, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// ── Rubric scoring row ─────────────────────────────────────────────
class _RubricRow extends StatelessWidget {
  final String label;
  final String rubricKey;
  final int value;
  final bool isSafety;
  final int safetyThreshold;
  final ValueChanged<int> onChanged;

  const _RubricRow({
    required this.label,
    required this.rubricKey,
    required this.value,
    required this.isSafety,
    required this.safetyThreshold,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGateFailed = isSafety && value > 0 && value < safetyThreshold;
    final barColor = isGateFailed
      ? const Color(0xFFEF4444)
      : value >= 4 ? const Color(0xFF22C55E) : const Color(0xFF3B82F6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isSafety) const Text('⚡ ', style: TextStyle(fontSize: 12)),
              Text(label,
                style: GoogleFonts.poppins(
                  color: Colors.white70, fontSize: 12,
                  fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: barColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6)),
                child: Text('$value / 5',
                  style: GoogleFonts.poppins(
                    color: barColor, fontSize: 11,
                    fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [1, 2, 3, 4, 5].map((i) {
              final selected = value == i;
              final filled = i <= value;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 32,
                    decoration: BoxDecoration(
                      color: filled ? barColor.withAlpha(80) : const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? barColor : Colors.transparent,
                        width: 2)),
                    alignment: Alignment.center,
                    child: Text('$i',
                      style: GoogleFonts.poppins(
                        color: filled ? Colors.white : Colors.white38,
                        fontSize: 13, fontWeight: FontWeight.bold))),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

Widget _SectionLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text(text,
    style: GoogleFonts.poppins(
      color: Colors.white54, fontSize: 11,
      fontWeight: FontWeight.w700, letterSpacing: 0.5)),
);
