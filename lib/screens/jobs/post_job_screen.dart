// lib/screens/jobs/post_job_screen.dart
// Phase 5: Guided Multi-Step Job Posting Workflow for Hirers.
// Enforces Two-Tier Location Disclosure, Skill Taxonomy, Fair Wage Guidance,
// and Idempotent Batch Firestore Creation.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../models/work_location.dart';
import '../../providers/auth_provider.dart';
import '../../providers/jobs_provider.dart';
import '../location/select_work_location_screen.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  int _currentStep = 0;
  final int _totalSteps = 6;

  // Step 1: Work Needed
  String _selectedSkill = 'mason';
  final _titleController = TextEditingController();
  final _titleKnController = TextEditingController();

  // Step 2: Description & Scope
  final _descController = TextEditingController();
  final _materialsController = TextEditingController();

  // Step 3: Schedule & Duration
  String _jobType = 'Daily Wage';
  int _durationDays = 1;
  bool _urgent = false;

  // Step 4: Two-Tier Location
  WorkLocation? _workLocation;

  // Step 5: Budget & Pay
  double _pay = 750;
  bool _negotiable = false;

  // State
  bool _isPublishing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController.text = 'Skilled Mason Needed for House Construction';
    _titleKnController.text = 'ಮನೆ ನಿರ್ಮಾಣಕ್ಕೆ ಪರಿಣಿತ ಮೇಸ್ತ್ರಿ ಬೇಕಾಗಿದ್ದಾರೆ';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleKnController.dispose();
    _descController.dispose();
    _materialsController.dispose();
    super.dispose();
  }

  void _onSkillSelected(String skillId) {
    setState(() {
      _selectedSkill = skillId;
      final cat = kJobCategories.firstWhere((c) => c.id == skillId, orElse: () => kJobCategories.first);
      if (_titleController.text.isEmpty || _titleController.text.contains('Needed')) {
        _titleController.text = '${cat.label} Needed';
        _titleKnController.text = '${cat.labelKn} ಕೆಲಸಗಾರರು ಬೇಕಾಗಿದ್ದಾರೆ';
      }
    });
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<WorkLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectWorkLocationScreen(initial: _workLocation),
      ),
    );
    if (result != null && result.isValid) {
      setState(() {
        _workLocation = result;
        _errorMessage = null;
      });
    }
  }

  bool _validateCurrentStep() {
    setState(() => _errorMessage = null);
    switch (_currentStep) {
      case 0:
        if (_selectedSkill.isEmpty) {
          setState(() => _errorMessage = 'Please select a skill category');
          return false;
        }
        if (_titleController.text.trim().isEmpty) {
          setState(() => _errorMessage = 'Please enter a job title');
          return false;
        }
        return true;
      case 1:
        if (_descController.text.trim().isEmpty) {
          setState(() => _errorMessage = 'Please describe the work needed');
          return false;
        }
        return true;
      case 2:
        return true;
      case 3:
        if (_workLocation == null || !_workLocation!.isValid) {
          setState(() => _errorMessage = 'Please select an exact work site location');
          return false;
        }
        return true;
      case 4:
        if (_pay < 300) {
          setState(() => _errorMessage = 'Minimum wage is ₹300/day');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (_validateCurrentStep()) {
      if (_currentStep < _totalSteps - 1) {
        setState(() => _currentStep++);
      } else {
        _publishJob();
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
    } else {
      Navigator.pop(context);
    }
  }

  // B14 FIX: Save job as draft to Firestore
  Future<void> _saveDraft() async {
    final auth = context.read<AuthProvider>();
    if (auth.uid == null) return;
    HapticFeedback.mediumImpact();
    try {
      await FirebaseFirestore.instance.collection('jobs').add({
        'hirerId': auth.uid,
        'hirerName': auth.name,
        'status': 'draft',
        'title': _titleController.text.trim(),
        'titleKn': _titleKnController.text.trim(),
        'description': _descController.text.trim(),
        'skill': _selectedSkill,
        'jobType': _jobType,
        'durationDays': _durationDays,
        'urgent': _urgent,
        'pay': _pay.round(),
        'district': _workLocation?.district ?? '',
        'taluk': _workLocation?.taluk ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '📝 ಡ್ರಾಫ್ಟ್ ಉಳಿಸಲಾಗಿದೆ / Draft saved',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, fontSize: 13),
          ),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Save draft error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ಉಳಿಸಲಾಗಲಿಲ್ಲ / Could not save draft',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _publishJob() async {
    final auth = context.read<AuthProvider>();
    final jobsProvider = context.read<JobsProvider>();

    if (auth.uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to post a job')),
      );
      return;
    }

    if (_workLocation == null || !_workLocation!.isValid) {
      setState(() => _errorMessage = 'Work location is required');
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final cat = kJobCategories.firstWhere(
        (c) => c.id == _selectedSkill,
        orElse: () => kJobCategories.first,
      );

      final fullDescription = StringBuffer(_descController.text.trim());
      if (_materialsController.text.trim().isNotEmpty) {
        fullDescription.write('\n\nMaterials & Tools:\n${_materialsController.text.trim()}');
      }
      if (_durationDays > 1) {
        fullDescription.write('\nEstimated Duration: $_durationDays days');
      }
      if (_negotiable) {
        fullDescription.write('\nWages negotiable upon site inspection.');
      }

      final newJob = Job(
        id: '',
        title: _titleController.text.trim(),
        titleKn: _titleKnController.text.trim().isNotEmpty
            ? _titleKnController.text.trim()
            : _titleController.text.trim(),
        skill: _selectedSkill,
        skillIcon: cat.emoji,
        hirer: auth.name.isNotEmpty ? auth.name : 'Hirer',
        hirerId: auth.uid!,
        district: _workLocation!.district,
        taluk: _workLocation!.taluk,
        village: _workLocation!.village,
        pay: _pay.toInt(),
        jobType: _jobType,
        urgent: _urgent,
        description: fullDescription.toString(),
        workLocation: _workLocation,
      );

      final jobId = await jobsProvider.postJob(newJob);

      if (!mounted) return;

      if (jobId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              '🎉 Job published successfully! Workers can now apply.',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        );
        Navigator.pop(context, jobId);
      } else {
        setState(() {
          _isPublishing = false;
          _errorMessage = jobsProvider.lastPostError ?? 'Could not publish job. Please check your connection and try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _errorMessage = 'Error publishing job: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textHead),
          onPressed: _prevStep,
        ),
        title: Text(
          'Post a Job (${_currentStep + 1}/$_totalSteps)',
          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead),
        ),
        actions: [
          // B14 FIX: Save Draft button
          TextButton(
            onPressed: _saveDraft,
            child: Text('ಡ್ರಾಫ್ಟ್ / Draft',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textMed),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.red.withAlpha(25),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStepContent(),
              ),
            ),

            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1WorkNeeded();
      case 1:
        return _buildStep2DescriptionScope();
      case 2:
        return _buildStep3Schedule();
      case 3:
        return _buildStep4TwoTierLocation();
      case 4:
        return _buildStep5BudgetPay();
      case 5:
        return _buildStep6ReviewPublish();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 1: Work Needed ──
  Widget _buildStep1WorkNeeded() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('What work do you need done?', 'Select a trade and provide a clear title.'),
        const SizedBox(height: 16),
        _fieldLabel('Select Skill / Trade *'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kJobCategories.map((cat) {
            final isSelected = _selectedSkill == cat.id;
            return GestureDetector(
              onTap: () => _onSkillSelected(cat.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryPale : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Text(
                  '${cat.emoji} ${cat.label}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppColors.primary : AppColors.textBody,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _fieldLabel('Job Title (English) *'),
        TextField(
          controller: _titleController,
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textHead, fontWeight: FontWeight.w600),
          decoration: _inputDecoration('e.g. Master Carpenter for Kitchen Cabinets'),
        ),
        const SizedBox(height: 14),
        _fieldLabel('Job Title (Kannada / ಕನ್ನಡ)'),
        TextField(
          controller: _titleKnController,
          style: GoogleFonts.notoSansKannada(fontSize: 14, color: AppColors.textHead, fontWeight: FontWeight.w600),
          decoration: _inputDecoration('ಉದಾ: ಅಡುಗೆ ಮನೆ ಕಪಾಟು ಕೆಲಸಕ್ಕೆ ಬಡಗಿ ಬೇಕಾಗಿದ್ದಾರೆ'),
        ),
      ],
    );
  }

  // ── Step 2: Description & Scope ──
  Widget _buildStep2DescriptionScope() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Describe the Work', 'Clear details help experienced workers provide faster responses.'),
        const SizedBox(height: 16),
        _fieldLabel('Work Scope & Details *'),
        TextField(
          controller: _descController,
          maxLines: 5,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead),
          decoration: _inputDecoration(
            'Detail the exact requirements:\n• Nature of the task\n• Estimated area or volume\n• Specific techniques or finishes expected',
          ),
        ),
        const SizedBox(height: 16),
        _fieldLabel('Materials & Equipment Provided'),
        TextField(
          controller: _materialsController,
          maxLines: 3,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead),
          decoration: _inputDecoration(
            'e.g. Cement, sand, and scaffolding available on site. Worker brings own hand tools.',
          ),
        ),
      ],
    );
  }

  // ── Step 3: Schedule & Duration ──
  Widget _buildStep3Schedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Schedule & Urgency', 'When do you need the work to start?'),
        const SizedBox(height: 16),
        _fieldLabel('Contract Type'),
        Row(
          children: [
            Expanded(
              child: _radioCard(
                title: 'Daily Wage',
                subtitle: 'Pay per day worked',
                selected: _jobType == 'Daily Wage',
                onTap: () => setState(() => _jobType = 'Daily Wage'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _radioCard(
                title: 'Contract / Fixed',
                subtitle: 'Fixed job payout',
                selected: _jobType == 'Contract',
                onTap: () => setState(() => _jobType = 'Contract'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _fieldLabel('Estimated Days: $_durationDays day(s)'),
        Slider(
          value: _durationDays.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() => _durationDays = v.toInt()),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt, color: AppColors.red, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Urgent Requirement',
                      style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Text(
                      'Highlights job in red for available workers nearby',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _urgent,
                onChanged: (val) => setState(() => _urgent = val),
                activeThumbColor: AppColors.red,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 4: Two-Tier Location ──
  Widget _buildStep4TwoTierLocation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Work Site Location', 'Set your site location with privacy protection.'),
        const SizedBox(height: 12),

        // Two-Tier Privacy Notice Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Two-Tier Location Privacy Gate',
                      style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF1E40AF)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Public to all workers: District, Taluk, and Locality.\n• Private to accepted worker: Exact address, house number, GPS pin, and map navigation directions.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF1E3A8A), height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        if (_workLocation == null || !_workLocation!.isValid) ...[
          GestureDetector(
            onTap: _pickLocation,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: Column(
                children: [
                  const Icon(Icons.add_location_alt_outlined, color: AppColors.primary, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'Select Work Location on Map',
                    style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to search or drop pin at work site',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.green, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Work Site Confirmed',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _pickLocation,
                      child: Text(
                        'Change Pin',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _workLocation!.address,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textBody, height: 1.4),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_workLocation!.district.isNotEmpty) _locBadge('📍 ${_workLocation!.district}'),
                    if (_workLocation!.taluk.isNotEmpty) _locBadge('🏘 ${_workLocation!.taluk}'),
                    if (_workLocation!.village.isNotEmpty) _locBadge('🌿 ${_workLocation!.village}'),
                    if (_workLocation!.pincode.isNotEmpty) _locBadge('📮 ${_workLocation!.pincode}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 5: Budget & Pay ──
  Widget _buildStep5BudgetPay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Budget & Compensation', 'Fair wages attract experienced, reliable workers.'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text(
                '₹${_pay.toInt()}',
                style: GoogleFonts.sora(fontSize: 40, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
              ),
              Text(
                'per ${_jobType == "Contract" ? "job" : "day"}',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Slider(
                value: _pay,
                min: 300,
                max: 3000,
                divisions: 54,
                activeColor: const Color(0xFF059669),
                onChanged: (v) => setState(() => _pay = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('₹300 Min', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint)),
                  Text('₹1,500 Typical', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint)),
                  Text('₹3,000 High Skill', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Checkbox(
              value: _negotiable,
              onChanged: (val) => setState(() => _negotiable = val ?? false),
              activeColor: AppColors.primary,
            ),
            Expanded(
              child: Text(
                'Wages negotiable upon on-site work inspection',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textBody, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.handshake_outlined, color: AppColors.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Zero Platform Fee: 100% of this amount goes straight into the worker’s pocket upon job completion.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textBody, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 6: Review & Publish ──
  Widget _buildStep6ReviewPublish() {
    final cat = kJobCategories.firstWhere((c) => c.id == _selectedSkill, orElse: () => kJobCategories.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Review & Confirm', 'Verify the job specifications before publishing.'),
        const SizedBox(height: 16),

        // Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryPale,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: Text(cat.emoji, style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _titleController.text,
                          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textHead),
                        ),
                        Text(
                          '${cat.label} • $_jobType',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${_pay.toInt()}',
                    style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                  ),
                ],
              ),
              const Divider(height: 24),
              _summaryRow('Description', _descController.text),
              const SizedBox(height: 8),
              _summaryRow('Public Area', '${_workLocation?.taluk ?? ""}, ${_workLocation?.district ?? ""}'),
              const SizedBox(height: 8),
              _summaryRow('Private Site Address', _workLocation?.address ?? '', isPrivate: true),
              const SizedBox(height: 8),
              _summaryRow('Urgency', _urgent ? '🔴 Urgent' : 'Standard'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.greenPale,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Once published, qualified workers nearby will be able to review and apply.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final isLastStep = _currentStep == _totalSteps - 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: _isPublishing ? null : _prevStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textBody,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'Back',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isPublishing ? null : _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: isLastStep ? AppColors.green : AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isPublishing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      isLastStep ? 'Publish Job Now 🚀' : 'Next Step →',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textHead)),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight)),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textHead)),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textFaint),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      contentPadding: const EdgeInsets.all(14),
    );
  }

  Widget _radioCard({required String title, required String subtitle, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryPale : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: selected ? AppColors.primary : AppColors.textHead)),
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
          ],
        ),
      ),
    );
  }

  Widget _locBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textBody)),
    );
  }

  Widget _summaryRow(String label, String value, {bool isPrivate = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              if (isPrivate) const Icon(Icons.lock, size: 12, color: AppColors.primary),
              if (isPrivate) const SizedBox(width: 4),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHead),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
