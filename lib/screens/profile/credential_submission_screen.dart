// lib/screens/profile/credential_submission_screen.dart
// Worker screen to submit professional credential evidence.
// IMPORTANT: document submitted != credential verified.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/credential_service.dart';
import '../../models/credential_record.dart';
import '../../core/theme/app_colors.dart';

class CredentialSubmissionScreen extends StatefulWidget {
  final String skillId;
  final String skillName;
  const CredentialSubmissionScreen({
    super.key, required this.skillId, required this.skillName,
  });
  @override State<CredentialSubmissionScreen> createState() => _State();
}

class _State extends State<CredentialSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  CredentialType _type = CredentialType.dgtNtc;
  final _issuerCtrl       = TextEditingController();
  final _credNameCtrl     = TextEditingController();
  final _qualCodeCtrl     = TextEditingController();
  final _certNumCtrl      = TextEditingController();
  final _holderCtrl       = TextEditingController();
  final _verUrlCtrl       = TextEditingController();
  DateTime? _issueDate;
  DateTime? _expiryDate;
  File? _docFile;
  bool _submitting = false;
  String? _successId;

  static const _bg  = Color(0xFF0F172A);
  static const _card= Color(0xFF1E293B);
  static const _dim = Color(0xFF94A3B8);

  @override
  void dispose() {
    _issuerCtrl.dispose(); _credNameCtrl.dispose(); _qualCodeCtrl.dispose();
    _certNumCtrl.dispose(); _holderCtrl.dispose(); _verUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _docFile = File(picked.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = context.read<AuthProvider>().currentUser?.uid;
    if (uid == null) return;
    setState(() => _submitting = true);
    try {
      final id = await CredentialService.instance.submitCredential(
        workerId:         uid,
        skillId:          widget.skillId,
        credentialType:   _type,
        issuer:           _issuerCtrl.text.trim(),
        issuerType:       _type == CredentialType.dgtNtc ? 'DGT' : 'SSC',
        credentialName:   _credNameCtrl.text.trim(),
        qualificationCode:_qualCodeCtrl.text.trim(),
        credentialNumber: _certNumCtrl.text.trim(),
        holderName:       _holderCtrl.text.trim(),
        issueDate:        _issueDate,
        expiryDate:       _expiryDate,
        verificationUrl:  _verUrlCtrl.text.trim().isEmpty ? null : _verUrlCtrl.text.trim(),
        documentFile:     _docFile,
      );
      setState(() { _submitting = false; _successId = id; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credential submitted — pending review'), backgroundColor: Color(0xFF10B981)));
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Submit Credential', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Skill label
            Text('For: ${widget.skillName}', style: GoogleFonts.sora(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            // Disclaimer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF78350F).withAlpha(80), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFF59E0B).withAlpha(100))),
              child: Text('Document submitted ≠ Credential Verified.\nYour document will be reviewed against the official issuer record. Verification may take 2–5 working days.',
                style: GoogleFonts.sora(color: const Color(0xFFFBBF24), fontSize: 12)),
            ),
            const SizedBox(height: 20),
            _label('Credential Type'),
            _card_(DropdownButtonFormField<CredentialType>(
              value: _type,
              dropdownColor: _card,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Select credential type'),
              items: CredentialType.values.map((t) =>
                DropdownMenuItem(value: t, child: Text(t.displayName, style: const TextStyle(color: Colors.white, fontSize: 13)))).toList(),
              onChanged: (v) { if (v != null) setState(() => _type = v); },
            )),
            const SizedBox(height: 12),
            _label('Issuing Body Name'), _field(_issuerCtrl, 'e.g. DGT, NSDC, CSDCI', required: true),
            const SizedBox(height: 12),
            _label('Credential / Certificate Name'), _field(_credNameCtrl, 'e.g. National Trade Certificate in Painter', required: true),
            const SizedBox(height: 12),
            _label('Qualification Code (if any)'), _field(_qualCodeCtrl, 'e.g. CON/Q1303'),
            const SizedBox(height: 12),
            _label('Certificate / Registration Number'), _field(_certNumCtrl, 'As printed on certificate', required: true),
            const SizedBox(height: 12),
            _label('Name on Certificate'), _field(_holderCtrl, 'Exact name on document', required: true),
            const SizedBox(height: 12),
            _label('Verification URL (optional)'), _field(_verUrlCtrl, 'Official URL to verify this certificate'),
            const SizedBox(height: 12),
            // Date pickers
            Row(children: [
              Expanded(child: _datePicker('Issue Date', _issueDate, (d) => setState(() => _issueDate = d))),
              const SizedBox(width: 10),
              Expanded(child: _datePicker('Expiry Date', _expiryDate, (d) => setState(() => _expiryDate = d))),
            ]),
            const SizedBox(height: 16),
            // Document upload
            InkWell(
              onTap: _pickDocument,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _docFile != null ? const Color(0xFF10B981) : const Color(0xFF334155))),
                child: Row(children: [
                  Icon(_docFile != null ? Icons.check_circle : Icons.upload_file,
                    color: _docFile != null ? const Color(0xFF10B981) : _dim),
                  const SizedBox(width: 12),
                  Text(_docFile != null ? 'Document selected ✓' : 'Upload Document Image (optional)',
                    style: GoogleFonts.sora(color: _docFile != null ? const Color(0xFF10B981) : _dim, fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Text('Submit Credential', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
            if (_successId != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFF064E3B), borderRadius: BorderRadius.circular(10)),
                child: Text('✅ Submitted. Reference ID: $_successId\nAdmin will review against official records.',
                  style: GoogleFonts.sora(color: const Color(0xFF6EE7B7), fontSize: 12)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)));

  Widget _field(TextEditingController c, String hint, {bool required = false}) =>
    TextFormField(
      controller: c,
      style: GoogleFonts.sora(color: Colors.white, fontSize: 13),
      decoration: _dec(hint),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
    );

  Widget _card_(Widget child) => child;

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
    filled: true, fillColor: _card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primary)),
  );

  Widget _datePicker(String label, DateTime? value, ValueChanged<DateTime?> onPick) =>
    InkWell(
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: value ?? DateTime(2020), firstDate: DateTime(1990), lastDate: DateTime(2040));
        if (d != null) onPick(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF334155))),
        child: Text(value != null ? '${value.day}/${value.month}/${value.year}' : label,
          style: GoogleFonts.sora(color: value != null ? Colors.white : const Color(0xFF475569), fontSize: 12)),
      ),
    );
}
