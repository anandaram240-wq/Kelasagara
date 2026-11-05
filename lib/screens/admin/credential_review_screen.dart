// lib/screens/admin/credential_review_screen.dart
// Admin manual source verification for professional credentials.
// Admin reviews document, checks official source, sets evidence strength.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/credential_service.dart';
import '../../services/skill_verification_engine.dart';
import '../../models/credential_record.dart';
import '../../core/theme/app_colors.dart';

class CredentialReviewScreen extends StatefulWidget {
  final CredentialRecord credential;
  const CredentialReviewScreen({super.key, required this.credential});
  @override State<CredentialReviewScreen> createState() => _State();
}

class _State extends State<CredentialReviewScreen> {
  final _sourceUrlCtrl = TextEditingController();
  final _notesCtrl     = TextEditingController();
  final _stdVerCtrl    = TextEditingController(text: 'v1.0');
  CredentialStatus _decision = CredentialStatus.sourceChecked;
  bool _submitting = false;

  static const _bg   = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);

  @override void dispose() { _sourceUrlCtrl.dispose(); _notesCtrl.dispose(); _stdVerCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final adminId = context.read<AuthProvider>().currentUser?.uid ?? '';
    if (adminId.isEmpty) return;

    final strength = switch (_decision) {
      CredentialStatus.issuerConfirmed   => EvidenceStrength.issuerConfirmed,
      CredentialStatus.credentialVerified=> EvidenceStrength.authorizedDigitalVerification,
      CredentialStatus.sourceChecked     => EvidenceStrength.publicSourceChecked,
      CredentialStatus.rejected          => EvidenceStrength.selfDeclared,
      _                                  => EvidenceStrength.documentReviewed,
    };

    setState(() => _submitting = true);
    try {
      await CredentialService.instance.adminUpdateCredentialStatus(
        credentialId:      widget.credential.credentialId,
        workerId:          widget.credential.workerId,
        newStatus:         _decision,
        newStrength:       strength,
        adminId:           adminId,
        verificationMethod:'public_source',
        verificationSource:_sourceUrlCtrl.text.trim().isEmpty ? null : _sourceUrlCtrl.text.trim(),
        reviewNotes:       _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        standardVersion:   _stdVerCtrl.text.trim().isEmpty ? null : _stdVerCtrl.text.trim(),
      );

      // If issuer confirmed, evaluate for skill verification
      if (_decision == CredentialStatus.issuerConfirmed || _decision == CredentialStatus.credentialVerified) {
        final result = await SkillVerificationEngine.instance.evaluate(
          workerId: widget.credential.workerId,
          skillId:  widget.credential.skillId,
        );
        if (result.canVerify && mounted) {
          _showSkillVerifyDialog(adminId, result);
          return;
        }
      }

      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review submitted'), backgroundColor: Color(0xFF10B981)));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    }
  }

  void _showSkillVerifyDialog(String adminId, dynamic result) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: _card,
      title: Text('Mark Skill Verified?', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700)),
      content: Text('Credential is issuer-confirmed. Worker identity is verified.\nMark "${widget.credential.skillId}" as Skill Verified now?',
        style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 13)),
      actions: [
        TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: Text('Later', style: GoogleFonts.sora(color: const Color(0xFF94A3B8)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
          onPressed: () async {
            Navigator.pop(context);
            await SkillVerificationEngine.instance.markSkillVerified(
              workerId: widget.credential.workerId,
              skillId:  widget.credential.skillId,
              result:   result,
              adminId:  adminId,
              standardVersion: _stdVerCtrl.text.trim().isEmpty ? null : _stdVerCtrl.text.trim(),
            );
            setState(() => _submitting = false);
            if (mounted) Navigator.pop(context);
          },
          child: Text('Mark Verified', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.credential;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card, elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Credential Review', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Credential summary
          _section('Credential Details', [
            _row('Type',   c.credentialType.displayName),
            _row('Issuer', c.issuer),
            _row('Cert Name', c.credentialName),
            _row('Qual Code', c.qualificationCode.isEmpty ? '—' : c.qualificationCode),
            _row('Cert No.', c.credentialNumber),
            _row('Holder',  c.holderName),
            if (c.issueDate != null) _row('Issue Date', '${c.issueDate!.day}/${c.issueDate!.month}/${c.issueDate!.year}'),
            if (c.expiryDate != null) _row('Expiry', '${c.expiryDate!.day}/${c.expiryDate!.month}/${c.expiryDate!.year}'),
            _row('Worker ID', c.workerId),
            _row('Skill', c.skillId),
            _row('Submitted', c.submittedAt.toLocal().toString().substring(0,16)),
          ]),
          const SizedBox(height: 16),
          // Document image
          if (c.documentDownloadUrl != null) ...[
            _sectionHeader('Document Image'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(c.documentDownloadUrl!, height: 200, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(height: 80, color: _card, child: const Center(child: Text('Image unavailable', style: TextStyle(color: Colors.white38))))),
            ),
            const SizedBox(height: 16),
          ],
          // Verification URL
          if (c.verificationUrl != null && c.verificationUrl!.isNotEmpty) ...[
            _sectionHeader('Worker-provided Verification URL'),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => launchUrl(Uri.parse(c.verificationUrl!), mode: LaunchMode.externalApplication),
              child: Text(c.verificationUrl!, style: const TextStyle(color: Color(0xFF60A5FA), decoration: TextDecoration.underline, fontSize: 12))),
            const SizedBox(height: 16),
          ],
          // Admin input
          _section('Admin Verification', [
            _field(_sourceUrlCtrl, 'Source URL you checked (optional)'),
            const SizedBox(height: 10),
            _field(_notesCtrl, 'Review notes', maxLines: 3),
            const SizedBox(height: 10),
            _field(_stdVerCtrl, 'Standard version (e.g. v1.0)'),
          ]),
          const SizedBox(height: 16),
          // Decision
          _sectionHeader('Decision'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            CredentialStatus.sourceChecked,
            CredentialStatus.issuerConfirmed,
            CredentialStatus.rejected,
          ].map((s) => ChoiceChip(
            label: Text(s.displayLabel, style: GoogleFonts.sora(
              color: _decision == s ? Colors.white : const Color(0xFF94A3B8), fontSize: 12)),
            selected: _decision == s,
            selectedColor: s == CredentialStatus.rejected ? Colors.redAccent : const Color(0xFF10B981),
            backgroundColor: _card,
            onSelected: (_) => setState(() => _decision = s),
          )).toList()),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _decision == CredentialStatus.rejected ? Colors.redAccent : AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _submitting
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Text('Submit Review', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String t) => Text(t, style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14));

  Widget _section(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(title), const Divider(color: Color(0xFF334155), height: 16),
      ...children,
    ]),
  );

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110, child: Text(k, style: GoogleFonts.sora(color: const Color(0xFF64748B), fontSize: 12))),
      Expanded(child: Text(v, style: GoogleFonts.sora(color: Colors.white, fontSize: 12))),
    ]),
  );

  Widget _field(TextEditingController c, String hint, {int maxLines = 1}) =>
    TextField(controller: c, maxLines: maxLines,
      style: GoogleFonts.sora(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
        filled: true, fillColor: const Color(0xFF0F172A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
      ));
}
