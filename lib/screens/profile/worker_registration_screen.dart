import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../providers/auth_provider.dart';
import '../../services/worker_registration_service.dart';
import '../../models/worker_registration.dart';
import '../../core/theme/app_colors.dart';

class WorkerRegistrationScreen extends StatefulWidget {
  const WorkerRegistrationScreen({super.key});

  @override
  State<WorkerRegistrationScreen> createState() =>
      _WorkerRegistrationScreenState();
}

class _WorkerRegistrationScreenState extends State<WorkerRegistrationScreen> {
  final _refController = TextEditingController();
  final _occupationController = TextEditingController();
  RegistrationType _selectedType = RegistrationType.eShram;
  File? _documentFile;
  bool _submitting = false;
  String? _errorMsg;

  final _registrationTypes = ['e-Shram', 'Karnataka BOCW', 'Other'];

  @override
  void dispose() {
    _refController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _documentFile = File(picked.path));
    }
  }

  Future<void> _submit(String workerId) async {
    if (_refController.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Please enter the reference number.');
      return;
    }
    if (_occupationController.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Please enter the declared occupation.');
      return;
    }
    setState(() { _submitting = true; _errorMsg = null; });
    try {
      await WorkerRegistrationService.instance.submitRegistration(
        workerId: workerId,
        type: _selectedType,
        referenceNumber: _refController.text.trim(),
        declaredOccupation: _occupationController.text.trim(),
        documentFile: _documentFile,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
            content: Text(
              '✅ Registration evidence submitted for review.',
              style: GoogleFonts.sora(fontWeight: FontWeight.w700),
            ),
          ),
        );
        _refController.clear();
        _occupationController.clear();
        setState(() { _documentFile = null; _selectedType = RegistrationType.eShram; });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color _statusColor(RegistrationStatus status) {
    switch (status) {
      case RegistrationStatus.verified:
      case RegistrationStatus.sourceChecked:
        return AppColors.green;
      case RegistrationStatus.rejected:
        return AppColors.red;
      case RegistrationStatus.submitted:
      case RegistrationStatus.underReview:
        return const Color(0xFFF59E0B);
      default:
        return AppColors.textLight;
    }
  }

  IconData _statusIcon(RegistrationStatus status) {
    switch (status) {
      case RegistrationStatus.verified:
      case RegistrationStatus.sourceChecked:
        return Icons.verified;
      case RegistrationStatus.rejected:
        return Icons.cancel;
      case RegistrationStatus.submitted:
      case RegistrationStatus.underReview:
        return Icons.hourglass_empty;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final workerId = auth.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Worker Registration Evidence',
              style: GoogleFonts.sora(
                  fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
          Text('Submit e-Shram / BOCW evidence',
              style: GoogleFonts.sora(fontSize: 10, color: Colors.white70)),
        ]),
      ),
      body: workerId.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Header Card ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF3B82F6).withAlpha(80)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.badge_outlined, color: Color(0xFF3B82F6), size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Worker Registration Evidence',
                            style: GoogleFonts.sora(
                                fontSize: 15, fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E3A5F))),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      'Registration does not certify professional skill',
                      style: GoogleFonts.sora(
                          fontSize: 11, color: const Color(0xFF3B82F6),
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),

                const SizedBox(height: 16),

                // ── IMPORTANT Disclaimer ─────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF97316).withAlpha(100)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFF97316), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This registration evidence is reviewed separately from skill '
                        'competency. A verified e-Shram registration does NOT certify '
                        'professional skill.',
                        style: GoogleFonts.sora(
                            fontSize: 12, color: const Color(0xFF92400E),
                            fontWeight: FontWeight.w600, height: 1.5),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 24),
                Text('Registration Type',
                    style: GoogleFonts.sora(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.textHead)),
                const SizedBox(height: 8),

                // ── Registration Type Dropdown ────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<RegistrationType>(
                      value: _selectedType,
                      isExpanded: true,
                      style: GoogleFonts.sora(fontSize: 14, color: AppColors.textBody),
                      items: RegistrationType.values
                          .map((r) => DropdownMenuItem(value: r, child: Text(r.displayName)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedType = v);
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  _selectedType == RegistrationType.eShram
                      ? 'UAN (Universal Account Number)'
                      : _selectedType == 'Karnataka BOCW'
                          ? 'BOCW Card Number'
                          : 'Reference Number',
                  style: GoogleFonts.sora(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.textHead),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _refController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: _selectedType == RegistrationType.eShram
                        ? 'e.g. UAN1234567890'
                        : 'Enter reference number',
                    hintStyle: GoogleFonts.sora(
                        fontSize: 13, color: AppColors.textFaint),
                    prefixIcon: const Icon(Icons.numbers, color: AppColors.primary),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.primary, width: 2)),
                  ),
                ),

                const SizedBox(height: 16),
                Text('Declared Occupation on Card',
                    style: GoogleFonts.sora(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.textHead)),
                const SizedBox(height: 8),
                TextField(
                  controller: _occupationController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Mason, Electrician, Plumber',
                    hintStyle: GoogleFonts.sora(
                        fontSize: 13, color: AppColors.textFaint),
                    prefixIcon: const Icon(Icons.work_outline, color: AppColors.primary),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.primary, width: 2)),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Upload Document ──────────────────────────────────
                GestureDetector(
                  onTap: _pickDocument,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _documentFile != null
                          ? AppColors.primaryPale
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _documentFile != null
                              ? AppColors.primary
                              : AppColors.border,
                          style: BorderStyle.solid),
                    ),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: _documentFile != null
                              ? AppColors.primary
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _documentFile != null
                              ? Icons.check_circle
                              : Icons.upload_file,
                          color: _documentFile != null
                              ? Colors.white
                              : AppColors.textMed,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _documentFile != null
                              ? 'Document selected ✓'
                              : 'Upload Registration Document',
                          style: GoogleFonts.sora(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: _documentFile != null
                                  ? AppColors.primary
                                  : AppColors.textHead),
                        ),
                        Text(
                          _documentFile != null
                              ? _documentFile!.path.split('/').last
                              : 'Optional — JPEG/PNG of card',
                          style: GoogleFonts.sora(
                              fontSize: 11, color: AppColors.textLight),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ])),
                      if (_documentFile != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18,
                              color: AppColors.textMed),
                          onPressed: () => setState(() => _documentFile = null),
                        ),
                    ]),
                  ),
                ),

                if (_errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.redPale,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(_errorMsg!,
                        style: GoogleFonts.sora(
                            fontSize: 12, color: AppColors.red,
                            fontWeight: FontWeight.w600)),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Submit Button ────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : () => _submit(workerId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primary.withAlpha(120),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text('Submit Evidence',
                            style: GoogleFonts.sora(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Current Registration Status ──────────────────────
                Text('Registration Status',
                    style: GoogleFonts.sora(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: AppColors.textHead)),
                const SizedBox(height: 10),
                StreamBuilder<WorkerRegistration?>(
                  stream: WorkerRegistrationService.instance
                      .streamRegistration(workerId),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary));
                    }
                    final reg = snap.data;
                    if (reg == null) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text('No registration submitted yet.',
                            style: GoogleFonts.sora(
                                fontSize: 13, color: AppColors.textLight)),
                      );
                    }
                    final statusColor = _statusColor(reg.status);
                    final statusIcon = _statusIcon(reg.status);
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: statusColor.withAlpha(80)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(statusIcon, color: statusColor, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reg.registrationType.displayName,
                              style: GoogleFonts.sora(
                                  fontSize: 14, fontWeight: FontWeight.w800,
                                  color: AppColors.textHead),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              reg.status.displayLabel,
                              style: GoogleFonts.sora(
                                  fontSize: 10, fontWeight: FontWeight.w800,
                                  color: statusColor),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        _infoRow('Ref No.', reg.referenceNumber),
                        _infoRow('Occupation', reg.declaredOccupation),
                        if (reg.reviewNotes != null && reg.reviewNotes!.isNotEmpty)
                          _infoRow('Review Notes', reg.reviewNotes!),
                      ]),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ]),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 100,
          child: Text('$label:',
              style: GoogleFonts.sora(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textLight)),
        ),
        Expanded(
          child: Text(value,
              style: GoogleFonts.sora(
                  fontSize: 12, color: AppColors.textBody)),
        ),
      ]),
    );
  }
}
