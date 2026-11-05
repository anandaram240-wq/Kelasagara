// ================================================================
// KELASAGARA — Knowledge Assessment Screen
// Timed 15-question test. Bilingual (English + Kannada).
// No back navigation. Auto-submits on timeout.
// Scores written to Firestore by AssessmentService only.
// Workers cannot see score until admin reviews.
// ================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/skill_assessment.dart';
import '../../services/assessment_service.dart';
import 'practical_assessment_screen.dart';

class KnowledgeAssessmentScreen extends StatefulWidget {
  final String skillId;
  final String skillName;
  final String emoji;
  const KnowledgeAssessmentScreen({
    super.key,
    required this.skillId,
    required this.skillName,
    required this.emoji,
  });
  @override State<KnowledgeAssessmentScreen> createState() => _KnowledgeAssessmentScreenState();
}

class _KnowledgeAssessmentScreenState extends State<KnowledgeAssessmentScreen> {
  static const int _totalTimeSeconds = 20 * 60; // 20 minutes

  final _svc = AssessmentService.instance;

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  SkillAssessment? _assessment;
  List<AssessmentQuestion> _questions = [];
  int _current = 0;
  String? _selectedOptionId;
  final List<AssessmentAnswer> _answers = [];

  late Timer _timer;
  int _secondsLeft = _totalTimeSeconds;
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Create or resume existing assessment
      final assessment = await _svc.createAssessment(skillId: widget.skillId);
      if (assessment == null) throw Exception('Could not create assessment');

      await _svc.startAssessment(assessment.id);
      final questions = await _svc.loadQuestions(skillId: widget.skillId, count: 15);

      if (!mounted) return;
      setState(() {
        _assessment = assessment;
        _questions = questions;
        _loading = false;
      });

      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _submitAnswers(timedOut: true);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _next() async {
    if (_selectedOptionId == null) return;

    final q = _questions[_current];
    final correct = q.options.firstWhere(
      (o) => o.id == _selectedOptionId, orElse: () => q.options.first);

    _answers.add(AssessmentAnswer(
      questionId:     q.id,
      selectedOptionId: _selectedOptionId!,
      isCorrect:      correct.isCorrect,
      safetyRelated:  q.safetyRelated,
    ));

    if (_current < _questions.length - 1) {
      setState(() { _current++; _selectedOptionId = null; });
    } else {
      // Last question answered — submit
      _timer.cancel();
      await _submitAnswers(timedOut: false);
    }
  }

  Future<void> _submitAnswers({required bool timedOut}) async {
    if (_submitting || _assessment == null) return;
    setState(() => _submitting = true);

    try {
      final elapsed = DateTime.now().difference(_startTime);
      await _svc.submitKnowledgeAnswers(
        assessmentId: _assessment!.id,
        skillId:      widget.skillId,
        answers:      _answers,
        timeTaken:    elapsed,
      );

      if (!mounted) return;
      // Always go to practical assessment regardless of knowledge score
      // (admin will check both knowledge + practical before deciding)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PracticalAssessmentScreen(
          assessmentId: _assessment!.id,
          skillId:      widget.skillId,
          skillName:    widget.skillName,
          emoji:        widget.emoji,
        )),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = 'Submission error: $e'; });
    }
  }

  String get _timerDisplay {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor => _secondsLeft < 120
    ? const Color(0xFFEF4444)
    : _secondsLeft < 300
      ? const Color(0xFFF59E0B)
      : const Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Color(0xFF3B82F6)),
              const SizedBox(height: 16),
              Text('Preparing ${widget.skillName} Assessment...',
                style: const TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6)),
                  child: const Text('Go Back')),
              ],
            ),
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📋', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text('No questions available for ${widget.skillName} yet.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('Admin will add questions soon.',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  // Skip knowledge test and go directly to practical
                  if (_assessment != null) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => PracticalAssessmentScreen(
                        assessmentId: _assessment!.id,
                        skillId:      widget.skillId,
                        skillName:    widget.skillName,
                        emoji:        widget.emoji,
                      )));
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6)),
                child: const Text('Continue to Practical Assessment')),
            ],
          ),
        ),
      );
    }

    final question = _questions[_current];
    final progress = (_current + 1) / _questions.length;

    return PopScope(
      canPop: false, // No back navigation during test
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: _submitting
            ? _SubmittingOverlay(skillName: widget.skillName)
            : Column(
              children: [
                // ── Header ─────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  color: const Color(0xFF1E293B),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(widget.emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${widget.skillName} — Knowledge Test',
                              style: GoogleFonts.poppins(
                                color: Colors.white, fontSize: 14,
                                fontWeight: FontWeight.w700))),
                          // Timer
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _timerColor.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _timerColor.withAlpha(100))),
                            child: Row(children: [
                              Icon(Icons.timer_rounded,
                                color: _timerColor, size: 14),
                              const SizedBox(width: 4),
                              Text(_timerDisplay,
                                style: GoogleFonts.poppins(
                                  color: _timerColor,
                                  fontWeight: FontWeight.w800, fontSize: 13)),
                            ]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Progress bar
                      Row(
                        children: [
                          Text('Q ${_current + 1} / ${_questions.length}',
                            style: GoogleFonts.poppins(
                              color: Colors.white54, fontSize: 11)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: const Color(0xFF334155),
                                valueColor: const AlwaysStoppedAnimation(
                                  Color(0xFF3B82F6)),
                                minHeight: 6))),
                          const SizedBox(width: 8),
                          if (question.safetyRelated)
                            const Text('⚠️ Safety',
                              style: TextStyle(
                                color: Color(0xFFF59E0B), fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Question ───────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // English question
                        Text(question.questionText,
                          style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 17,
                            fontWeight: FontWeight.w600, height: 1.5))
                          .animate().fadeIn().slideY(begin: 0.1),

                        // Kannada question (if available)
                        if (question.questionTextKn.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(question.questionTextKn,
                            style: GoogleFonts.notoSansKannada(
                              color: Colors.white54, fontSize: 13, height: 1.5)),
                        ],

                        const SizedBox(height: 24),

                        // Options
                        ...question.options.asMap().entries.map((e) {
                          final opt = e.value;
                          final label = String.fromCharCode(65 + e.key); // A, B, C, D
                          final selected = _selectedOptionId == opt.id;

                          return GestureDetector(
                            onTap: () => setState(() => _selectedOptionId = opt.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: selected
                                  ? const Color(0xFF3B82F6).withAlpha(30)
                                  : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF334155),
                                  width: selected ? 2 : 1)),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28, height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selected
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF334155),
                                      shape: BoxShape.circle),
                                    child: Text(label,
                                      style: GoogleFonts.poppins(
                                        color: selected
                                          ? Colors.white
                                          : Colors.white54,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(opt.text,
                                      style: GoogleFonts.poppins(
                                        color: selected
                                          ? Colors.white
                                          : Colors.white70,
                                        fontSize: 14))),
                                  if (selected)
                                    const Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF3B82F6), size: 18),
                                ],
                              ),
                            ),
                          ).animate().fadeIn(delay: (e.key * 60).ms);
                        }),
                      ],
                    ),
                  ),
                ),

                // ── Next button ────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF1E293B),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _selectedOptionId != null ? _next : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        disabledBackgroundColor: const Color(0xFF334155),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                      child: Text(
                        _current < _questions.length - 1
                          ? 'Next Question →'
                          : 'Submit & Continue to Practical ✓',
                        style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w700))),
                  ),
                ),
              ],
            ),
        ),
      ),
    );
  }
}

class _SubmittingOverlay extends StatelessWidget {
  final String skillName;
  const _SubmittingOverlay({required this.skillName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF3B82F6)),
          const SizedBox(height: 24),
          Text('Saving your answers...',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Moving to Practical Assessment',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}
