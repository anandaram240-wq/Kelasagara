// ================================================================
// KELASAGARA — Practical Assessment Screen
// Worker records and uploads video evidence per task.
// Uses Firebase Storage (no Cloudflare, no billing).
// Clear task instructions + upload progress shown.
// ================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/evidence_upload_service.dart';
import '../../services/assessment_service.dart';
import 'assessment_result_screen.dart';

// ── Default practical tasks when Firestore standard not loaded ────
const _kDefaultTasks = [
  _DefaultTask(id: 'task_1', name: 'Task 1: Preparation',   nameKn: 'ಕಾರ್ಯ 1: ತಯಾರಿ',       hint: 'Show your preparation steps clearly. Include tools and materials.'),
  _DefaultTask(id: 'task_2', name: 'Task 2: Main Work',     nameKn: 'ಕಾರ್ಯ 2: ಮುಖ್ಯ ಕೆಲಸ',   hint: 'Show the main work being done. Include safety measures.'),
  _DefaultTask(id: 'task_3', name: 'Task 3: Quality Check', nameKn: 'ಕಾರ್ಯ 3: ಗುಣಮಟ್ಟ ಪರಿಶೀಲನೆ', hint: 'Show the finished work and explain any quality checks.'),
];

class _DefaultTask {
  final String id;
  final String name;
  final String nameKn;
  final String hint;
  const _DefaultTask({required this.id, required this.name, required this.nameKn, required this.hint});
}

class PracticalAssessmentScreen extends StatefulWidget {
  final String assessmentId;
  final String skillId;
  final String skillName;
  final String emoji;

  const PracticalAssessmentScreen({
    super.key,
    required this.assessmentId,
    required this.skillId,
    required this.skillName,
    required this.emoji,
  });
  @override State<PracticalAssessmentScreen> createState() => _PracticalAssessmentScreenState();
}

class _PracticalAssessmentScreenState extends State<PracticalAssessmentScreen> {
  final _uploader  = EvidenceUploadService.instance;
  final _svc       = AssessmentService.instance;
  final _picker    = ImagePicker();

  int _currentTask = 0;
  final Map<String, _TaskUploadState> _taskStates = {};

  bool _submitting = false;

  List<_DefaultTask> get _tasks => _kDefaultTasks;

  bool get _allTasksUploaded => _tasks.every(
    (t) => _taskStates[t.id]?.isDone == true);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _showExitDialog(context);
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white60),
            onPressed: () async {
              final leave = await _showExitDialog(context);
              if (leave && context.mounted) Navigator.of(context).pop();
            }),
          title: Text('${widget.emoji} ${widget.skillName} — Practical',
            style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          elevation: 0,
        ),
        body: Column(
          children: [
            // ── Task progress bar ──────────────────────────────────────
            _TaskProgressBar(
              tasks: _tasks,
              taskStates: _taskStates,
              currentTask: _currentTask,
            ),

            Expanded(
              child: _TaskCard(
                task: _tasks[_currentTask],
                state: _taskStates[_tasks[_currentTask].id],
                onRecord: () => _recordVideo(_tasks[_currentTask]),
                onPickGallery: () => _pickFromGallery(_tasks[_currentTask]),
                onRetake: () => setState(() {
                  _taskStates.remove(_tasks[_currentTask].id);
                }),
              ),
            ),

            // ── Navigation + Submit ───────────────────────────────────
            _BottomNav(
              currentTask: _currentTask,
              totalTasks: _tasks.length,
              canGoNext: _taskStates[_tasks[_currentTask].id]?.isDone == true,
              allDone: _allTasksUploaded,
              submitting: _submitting,
              onPrev: _currentTask > 0
                ? () => setState(() => _currentTask--)
                : null,
              onNext: () => setState(() => _currentTask++),
              onSubmit: _submitForReview,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordVideo(_DefaultTask task) async {
    try {
      final video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null) return;
      await _uploadFile(task, File(video.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _pickFromGallery(_DefaultTask task) async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      await _uploadFile(task, File(video.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gallery error: $e'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _uploadFile(_DefaultTask task, File file) async {
    setState(() {
      _taskStates[task.id] = _TaskUploadState(status: UploadState.validating);
    });

    final stream = _uploader.uploadEvidence(
      videoFile:    file,
      assessmentId: widget.assessmentId,
      taskId:       task.id,
      skillId:      widget.skillId,
    );

    await for (final progress in stream) {
      if (!mounted) return;
      setState(() {
        _taskStates[task.id] = _TaskUploadState(
          status:       progress.state,
          progress:     progress.progress,
          message:      progress.message,
          errorMessage: progress.errorMessage,
          evidenceId:   progress.evidenceId,
        );
      });

      if (progress.isDone || progress.hasFailed) break;
    }
  }

  Future<void> _submitForReview() async {
    if (!_allTasksUploaded || _submitting) return;

    setState(() => _submitting = true);
    try {
      await _svc.submitForReview(widget.assessmentId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AssessmentResultScreen(
          assessmentId: widget.assessmentId,
          skillName:    widget.skillName,
          emoji:        widget.emoji,
        )));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit error: $e'),
          backgroundColor: Colors.red));
    }
  }

  Future<bool> _showExitDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Exit Assessment?',
          style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(
          'Your uploaded videos are saved. You can come back later to complete the remaining tasks.',
          style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay', style: TextStyle(color: Color(0xFF3B82F6)))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    ) ?? false;
  }
}

// ── Task upload state ──────────────────────────────────────────────
class _TaskUploadState {
  final UploadState status;
  final double progress;
  final String message;
  final String? errorMessage;
  final String? evidenceId;

  const _TaskUploadState({
    required this.status,
    this.progress = 0,
    this.message = '',
    this.errorMessage,
    this.evidenceId,
  });

  bool get isDone    => status == UploadState.done;
  bool get hasFailed => status == UploadState.failed;
  bool get isActive  => status == UploadState.uploading || status == UploadState.validating;
}

// ── Task progress bar ──────────────────────────────────────────────
class _TaskProgressBar extends StatelessWidget {
  final List<_DefaultTask> tasks;
  final Map<String, _TaskUploadState> taskStates;
  final int currentTask;

  const _TaskProgressBar({
    required this.tasks,
    required this.taskStates,
    required this.currentTask,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF1E293B),
      child: Row(
        children: tasks.asMap().entries.map((e) {
          final state = taskStates[e.value.id];
          final isCurrent = e.key == currentTask;
          final isDone = state?.isDone == true;
          final isFailed = state?.hasFailed == true;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDone
                            ? const Color(0xFF22C55E)
                            : isCurrent
                              ? const Color(0xFF3B82F6)
                              : isFailed
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 4),
                      Text('Task ${e.key + 1}',
                        style: GoogleFonts.poppins(
                          color: isCurrent ? Colors.white : Colors.white38,
                          fontSize: 9,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400)),
                    ],
                  ),
                ),
                if (e.key < tasks.length - 1) const SizedBox(width: 4),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Individual task card ───────────────────────────────────────────
class _TaskCard extends StatelessWidget {
  final _DefaultTask task;
  final _TaskUploadState? state;
  final VoidCallback onRecord;
  final VoidCallback onPickGallery;
  final VoidCallback onRetake;

  const _TaskCard({
    required this.task,
    required this.state,
    required this.onRecord,
    required this.onPickGallery,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Task name
          Text(task.name,
            style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 20,
              fontWeight: FontWeight.bold))
            .animate().fadeIn(),

          Text(task.nameKn,
            style: GoogleFonts.notoSansKannada(
              color: Colors.white54, fontSize: 13)),

          const SizedBox(height: 16),

          // Instructions box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📹 What to show in your video:',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF3B82F6), fontSize: 12,
                    fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(task.hint,
                  style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 13, height: 1.6)),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF334155)),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.timer_outlined,
                    color: Color(0xFFF59E0B), size: 14),
                  const SizedBox(width: 6),
                  Text('Max 5 minutes · Max 200 MB',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFF59E0B), fontSize: 11)),
                ]),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Upload state
          if (state == null) ...[
            // No video yet — show buttons
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: onRecord,
                icon: const Icon(Icons.videocam_rounded, color: Colors.white),
                label: Text('Record Video',
                  style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w700,
                    fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))))),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onPickGallery,
                icon: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFF3B82F6), size: 18),
                label: Text('Upload from Gallery',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF3B82F6),
                    fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF3B82F6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))))),
          ] else if (state!.hasFailed) ...[
            _StatusCard(
              icon: '⚠️',
              message: state!.errorMessage ?? 'Upload failed',
              color: const Color(0xFFEF4444)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onRetake,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444)),
                child: const Text('Try Again'))),
          ] else if (state!.isDone) ...[
            _StatusCard(
              icon: '✅',
              message: 'Video uploaded securely',
              color: const Color(0xFF22C55E)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF94A3B8), size: 16),
              label: Text('Retake Video',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF94A3B8), fontSize: 12))),
          ] else ...[
            // In progress
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Text(state!.message,
                    style: GoogleFonts.poppins(
                      color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: state!.progress > 0 ? state!.progress : null,
                    backgroundColor: const Color(0xFF334155),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
                    minHeight: 6),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String icon;
  final String message;
  final Color color;
  const _StatusCard({required this.icon, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80))),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message,
            style: GoogleFonts.poppins(color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ── Bottom navigation ──────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int currentTask;
  final int totalTasks;
  final bool canGoNext;
  final bool allDone;
  final bool submitting;
  final VoidCallback? onPrev;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  const _BottomNav({
    required this.currentTask,
    required this.totalTasks,
    required this.canGoNext,
    required this.allDone,
    required this.submitting,
    required this.onPrev,
    required this.onNext,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = currentTask == totalTasks - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(top: BorderSide(color: Color(0xFF334155)))),
      child: Row(
        children: [
          if (onPrev != null)
            OutlinedButton(
              onPressed: onPrev,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF334155)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white60))
          else
            const SizedBox(width: 56),

          const SizedBox(width: 12),
          Expanded(
            child: isLast
              ? ElevatedButton(
                  onPressed: allDone && !submitting ? onSubmit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: allDone
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF334155),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
                  child: submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                    : Text(
                        allDone ? 'Submit for Review ✓' : 'Upload all tasks first',
                        style: GoogleFonts.poppins(
                          color: Colors.white, fontWeight: FontWeight.w700)))
              : ElevatedButton(
                  onPressed: canGoNext ? onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canGoNext
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF334155),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
                  child: Text(
                    canGoNext ? 'Next Task →' : 'Upload video first',
                    style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w700))),
          ),
        ],
      ),
    );
  }
}
