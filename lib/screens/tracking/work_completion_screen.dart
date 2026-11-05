// lib/screens/tracking/work_completion_screen.dart
// Hirer-side: confirm worker's completion request + give ratings.
// Only this screen's submission can create a VerifiedWorkRecord.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/verified_work_service.dart';

class WorkCompletionScreen extends StatefulWidget {
  final String bookingId;
  final String workerId;
  final String hirerId;
  final String jobId;
  final String skillId;
  final String workerName;
  final String jobTitle;

  const WorkCompletionScreen({
    super.key,
    required this.bookingId,
    required this.workerId,
    required this.hirerId,
    required this.jobId,
    required this.skillId,
    required this.workerName,
    required this.jobTitle,
  });

  @override
  State<WorkCompletionScreen> createState() => _WorkCompletionScreenState();
}

class _WorkCompletionScreenState extends State<WorkCompletionScreen> {
  double _quality         = 4.0;
  double _punctuality     = 4.0;
  double _safety          = 4.0;
  double _taskCompletion  = 4.0;
  double _communication   = 4.0;
  bool   _wouldHireAgain  = true;
  final  _commentsCtrl    = TextEditingController();
  bool   _isSubmitting    = false;
  String _error           = '';

  @override
  void dispose() {
    _commentsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() { _isSubmitting = true; _error = ''; });

    final auth = context.read<AuthProvider>();
    final effectiveHirerId = widget.hirerId.isNotEmpty ? widget.hirerId : (auth.uid ?? '');

    final result = await VerifiedWorkService.instance.confirmCompletion(
      bookingId:          widget.bookingId,
      workerId:           widget.workerId,
      hirerId:            effectiveHirerId,
      jobId:              widget.jobId,
      skillId:            widget.skillId,
      qualityScore:       _quality,
      punctualityScore:   _punctuality,
      safetyScore:        _safety,
      taskCompletionScore: _taskCompletion,
      communicationScore: _communication,
      wouldHireAgain:     _wouldHireAgain,
      comments:           _commentsCtrl.text.trim(),
    );

    if (!mounted) return;

    if (result.success) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Work verified! Worker\'s badge has been updated.'),
          backgroundColor: Color(0xFF22C55E),
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      setState(() {
        _isSubmitting = false;
        _error = result.error;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${result.error}'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _dispute() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _DisputeDialog(),
    );
    if (reason == null || reason.isEmpty) return;
    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    final effectiveHirerId = widget.hirerId.isNotEmpty ? widget.hirerId : (auth.uid ?? '');

    await VerifiedWorkService.instance.disputeCompletion(
      bookingId: widget.bookingId,
      hirerId:   effectiveHirerId,
      reason:    reason,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dispute filed. Admin will review shortly.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Confirm Work Done', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFF3B82F6),
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.workerName, style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(widget.jobTitle, style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF22C55E).withAlpha(30), borderRadius: BorderRadius.circular(20)),
                    child: Text('Work Done', style: GoogleFonts.sora(color: const Color(0xFF22C55E), fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Text('Rate the Work', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),

            _RatingRow('Work Quality',      _quality,        (v) => setState(() => _quality = v),        Icons.star_rounded),
            _RatingRow('Punctuality',        _punctuality,    (v) => setState(() => _punctuality = v),    Icons.access_time_rounded),
            _RatingRow('Safety',             _safety,         (v) => setState(() => _safety = v),         Icons.shield_rounded),
            _RatingRow('Task Completion',    _taskCompletion, (v) => setState(() => _taskCompletion = v), Icons.task_alt_rounded),
            _RatingRow('Communication',      _communication,  (v) => setState(() => _communication = v),  Icons.chat_bubble_rounded),

            const SizedBox(height: 20),
            // Would hire again
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Text('Would hire again?', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Switch(
                    value: _wouldHireAgain,
                    onChanged: (v) => setState(() => _wouldHireAgain = v),
                    activeThumbColor: const Color(0xFF3B82F6),
                    activeTrackColor: const Color(0xFF3B82F6).withAlpha(80),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            // Comments
            TextField(
              controller: _commentsCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Optional: Comments about the work...',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(color: Color(0xFFEF4444))),
            ],

            const SizedBox(height: 28),

            // Confirm button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('✅ Confirm — Work Verified', style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
              ),
            ),

            const SizedBox(height: 12),

            // Dispute button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : _dispute,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Report a Problem / Dispute', style: GoogleFonts.sora(color: const Color(0xFFEF4444), fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Rating row widget ──────────────────────────────────────────────────────────
class _RatingRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final IconData icon;

  const _RatingRow(this.label, this.value, this.onChanged, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF94A3B8), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: GoogleFonts.sora(color: const Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w500))),
            _StarRow(value, onChanged),
          ],
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _StarRow(this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starVal = (i + 1).toDouble();
        return GestureDetector(
          onTap: () => onChanged(starVal),
          child: Icon(
            value >= starVal ? Icons.star_rounded : Icons.star_outline_rounded,
            color: value >= starVal ? const Color(0xFFFBBF24) : const Color(0xFF475569),
            size: 26,
          ),
        );
      }),
    );
  }
}

// ── Dispute dialog ─────────────────────────────────────────────────────────────
class _DisputeDialog extends StatefulWidget {
  @override
  State<_DisputeDialog> createState() => _DisputeDialogState();
}

class _DisputeDialogState extends State<_DisputeDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: const Text('Report a Problem', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _ctrl,
        maxLines: 4,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Describe the issue...',
          hintStyle: TextStyle(color: Color(0xFF64748B)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
          child: const Text('Submit Dispute'),
        ),
      ],
    );
  }
}
