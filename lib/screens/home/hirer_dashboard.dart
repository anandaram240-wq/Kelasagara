import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../providers/auth_provider.dart';
import '../../providers/jobs_provider.dart';
import '../../models/work_location.dart';
import '../../services/chat_booking_service.dart';
import '../location/select_work_location_screen.dart';
import '../chat/chat_screen.dart';
import '../chat/conversations_screen.dart';
import '../../models/user_profile.dart';
import '../../widgets/worker_card.dart';
import '../../core/constants/karnataka_locations.dart';
import '../../services/worker_discovery_service.dart';
import '../../models/worker_search_request.dart';
import '../../models/worker_search_result.dart';
import '../profile/worker_profile_detail_screen.dart';
import '../jobs/post_job_screen.dart';
import '../jobs/job_applicants_screen.dart';
import '../jobs/work_detail_screen.dart';
import '../tracking/journey_navigator.dart';
import '../tracking/work_completion_screen.dart';
import 'package:latlong2/latlong.dart';

class HirerDashboard extends StatefulWidget {
  const HirerDashboard({super.key});
  @override State<HirerDashboard> createState() => _HirerDashboardState();
}

class _HirerDashboardState extends State<HirerDashboard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    // Start hirer-specific Firestore stream ONCE in initState (never in build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.uid != null) {
        context.read<JobsProvider>().startHirerStream(auth.uid!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final auth = context.watch<AuthProvider>();
    final jobs = context.watch<JobsProvider>();
    final myPosted = jobs.hirerJobs; // ← backed by dedicated hirer Firestore stream

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPostJobSheet(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Post Job', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: Colors.white)),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        strokeWidth: 3,
        displacement: 64,
        onRefresh: () async {
          await context.read<JobsProvider>().loadJobs();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.surface,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                content: Row(children: [
                  const Icon(Icons.check_circle, color: AppColors.green, size: 18),
                  const SizedBox(width: 8),
                  Text('Jobs updated', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textHead)),
                ]),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
        SliverAppBar(pinned: true, backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent, expandedHeight: 60,
          flexibleSpace: FlexibleSpaceBar(background: Container(color: AppColors.surface, padding: const EdgeInsets.fromLTRB(16,0,16,0),
            child: SafeArea(child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('ನಮಸ್ಕಾರ 🏢', style: GoogleFonts.notoSansKannada(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
                Text(auth.name, style: GoogleFonts.sora(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.textHead), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConversationsScreen())),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.primaryPale, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 40, height: 40, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF9F67FF)]), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 20)),
            ])))),
        ),

        // Stats
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [
          _statCard('📋', '${myPosted.length}', 'Posted', AppColors.primary),
          const SizedBox(width: 10),
          _statCard('⏳', '${myPosted.where((j) => j.status == "open").length}', 'Active', AppColors.violet),
          const SizedBox(width: 10),
          _statCard('✅', '${myPosted.where((j) => j.status == "filled").length}', 'Filled', AppColors.green),
          const SizedBox(width: 10),
          _statCard('💼', '${myPosted.where((j) => j.status == "closed").length}', 'Closed', const Color(0xFFF59E0B)),
        ]))),

        SliverToBoxAdapter(child: _ActiveHirerBookingCard(hirerId: auth.uid ?? '')),

        const SliverToBoxAdapter(child: _FindWorkersSection()),

        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('My Job Postings', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textHead)))),

        if (myPosted.isEmpty)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32), child: Column(children: [
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryPale, AppColors.violetPale],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('📋', style: TextStyle(fontSize: 52))),
            ),
            const SizedBox(height: 20),
            Text('Post Your First Job', style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead)),
            const SizedBox(height: 6),
            Text('Find skilled workers in Karnataka\nPlumbers, Electricians, Painters & more',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textLight, height: 1.5)),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _showPostJobSheet(context),
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
                label: Text('Post a Job', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              )),
          ])))
        else
          SliverList(delegate: SliverChildBuilderDelegate((ctx, i) {
            final job = myPosted[i];
            return RepaintBoundary(child: _hirerJobCard(ctx, job, i));
          }, childCount: myPosted.length)),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ])),
    );
  }

  Widget _hirerJobCard(BuildContext ctx, Job job, int i) {
    final statusColor = job.status == 'open' ? AppColors.green : job.status == 'filled' ? AppColors.violet : AppColors.textFaint;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          top: BorderSide(color: AppColors.border),
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
          left: BorderSide(
            color: job.status == 'open' ? AppColors.green
                : job.status == 'filled' ? AppColors.violet
                : AppColors.textFaint,
            width: 3,
          ),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
      ),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.violetPale, borderRadius: BorderRadius.circular(14)), child: Center(child: Text(job.skillIcon, style: const TextStyle(fontSize: 24)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(job.title, style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead)),
            Text('${job.taluk}, ${job.district}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
            Text('₹${job.pay} • ${job.jobType}', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.green)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: statusColor.withValues(alpha: 0.3))), child: Text(job.status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w900, color: statusColor))),
            const SizedBox(height: 4),
            Text('${job.applicants} applied', style: GoogleFonts.plusJakartaSans(fontSize: 9, color: AppColors.textFaint)),
          ]),
        ])),
        Container(height: 1, color: AppColors.divider),
        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12), child: Row(children: [
          GestureDetector(
            onTap: () => _showApplicants(ctx, job),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: job.status == 'filled' ? AppColors.violetPale : AppColors.primaryPale,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: job.status == 'filled' ? AppColors.violet.withValues(alpha: 0.3) : AppColors.primaryBorder),
              ),
              child: Text(
                job.status == 'filled'
                    ? 'Assigned Worker / Work Details →'
                    : 'View Applicants ${job.applicants > 0 ? "(${job.applicants})" : ""}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: job.status == 'filled' ? AppColors.violet : AppColors.primary,
                ),
              ),
            ),
          ),
          const Spacer(),
          if (job.status == 'open') GestureDetector(onTap: () async { context.read<JobsProvider>().closeJob(job.id); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: AppColors.redPale, borderRadius: BorderRadius.circular(10)), child: Text('Close', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.red)))),
        ])),
      ]),
    ).animate(delay: Duration(milliseconds: i * 50)).slideY(begin: 0.1, duration: 300.ms).fadeIn();
  }

  Widget _statCard(String emoji, String value, String label, Color color) =>
    Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(height: 6),
        Text(value, style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
      ]),
    ));

  void _showApplicants(BuildContext ctx, Job job) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => JobApplicantsScreen(
          jobId: job.id,
          jobTitle: job.title,
          skillId: job.skill,
          pay: job.pay,
        ),
      ),
    );
  }

  void _showPostJobSheet(BuildContext ctx) {
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => const PostJobScreen()),
    );
  }
}

// ── Post Job Sheet ─────────────────────────────────────────────────────────
class _PostJobSheet extends StatefulWidget {
  const _PostJobSheet();
  @override State<_PostJobSheet> createState() => _PostJobSheetState();
}

class _PostJobSheetState extends State<_PostJobSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  String        _skill       = '';
  String        _jobType     = 'Daily Wage';
  double        _pay         = 700;
  bool          _urgent      = false;
  WorkLocation? _workLocation;

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<WorkLocation>(
      context,
      MaterialPageRoute(builder: (_) => SelectWorkLocationScreen(initial: _workLocation)),
    );
    if (result != null && result.isValid) {
      setState(() => _workLocation = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(children: [
        const SizedBox(height: 8),
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)))),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Text('Post a Job', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textHead)),
          const Spacer(),
          GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: AppColors.textMed)),
        ])),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('Job Title / ಕೆಲಸದ ಹೆಸರು'),
          TextField(controller: _titleCtrl, decoration: const InputDecoration(hintText: 'e.g. Plumber Needed Urgently'), style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textHead)),
          const SizedBox(height: 14),
          _label('Skill Category / ಕೌಶಲ'),
          Wrap(spacing: 8, runSpacing: 8, children: kJobCategories.map((c) {
            final sel = _skill == c.id;
            return GestureDetector(onTap: () => setState(() => _skill = c.id), child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: sel ? AppColors.primaryPale : AppColors.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1)), child: Text('${c.emoji} ${c.label}', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? AppColors.primary : AppColors.textBody))));
          }).toList()),
          const SizedBox(height: 16),

          // ── WORK LOCATION (MANDATORY) ─────────────────────────────────────
          _label('Work Location / ಕೆಲಸದ ಸ್ಥಳ *'),
          if (_workLocation == null || !_workLocation!.isValid) ...[
            GestureDetector(
              onTap: _openLocationPicker,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFC107), width: 1.5)),
                child: Row(children: [
                  const Icon(Icons.add_location_alt, color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Select Exact Work Location', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                    Text('Required before posting • Tap to open map', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMed)),
                  ])),
                  const Icon(Icons.chevron_right, color: AppColors.textMed),
                ]),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.greenPale, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.green, width: 1.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.check_circle, color: AppColors.green, size: 18),
                  const SizedBox(width: 6),
                  Text('Work Location Confirmed', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.green)),
                  const Spacer(),
                  GestureDetector(onTap: _openLocationPicker, child: Text('Change', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary))),
                ]),
                const SizedBox(height: 8),
                Text(_workLocation!.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textBody)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  if (_workLocation!.district.isNotEmpty) _chip('📍 ${_workLocation!.district}'),
                  if (_workLocation!.taluk.isNotEmpty)    _chip('🏘 ${_workLocation!.taluk}'),
                  if (_workLocation!.village.isNotEmpty)  _chip('🌿 ${_workLocation!.village}'),
                  if (_workLocation!.pincode.isNotEmpty)  _chip('📮 ${_workLocation!.pincode}'),
                ]),
                const SizedBox(height: 4),
                Text('${_workLocation!.lat.toStringAsFixed(5)}°N, ${_workLocation!.lng.toStringAsFixed(5)}°E', style: GoogleFonts.plusJakartaSans(fontSize: 9, color: AppColors.textFaint)),
              ]),
            ),
          ],

          const SizedBox(height: 14),
          _label('Daily Pay / ದಿನ ಕೂಲಿ: ₹${_pay.toInt()}'),
          Slider(value: _pay, min: 300, max: 2000, divisions: 34, activeColor: AppColors.primary, onChanged: (v) => setState(() => _pay = v)),
          const SizedBox(height: 8),
          _label('Job Type'),
          Wrap(spacing: 8, children: ['Daily Wage', 'Weekly Contract', 'Project Based', 'Full-time'].map((t) {
            final sel = _jobType == t;
            return GestureDetector(onTap: () => setState(() => _jobType = t), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: sel ? AppColors.primaryPale : AppColors.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1)), child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? AppColors.primary : AppColors.textBody))));
          }).toList()),
          const SizedBox(height: 14),
          _label('Description / ವಿವರ'),
          TextField(controller: _descCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Describe the work, requirements, tools provided...')),
          const SizedBox(height: 12),
          Row(children: [
            Switch(value: _urgent, activeTrackColor: AppColors.red.withValues(alpha: 0.3), activeThumbColor: AppColors.red, onChanged: (v) => setState(() => _urgent = v)),
            Text('Mark as Urgent 🔴', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: _urgent ? AppColors.red : AppColors.textMed)),
          ]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 52, child: Consumer<JobsProvider>(
            builder: (ctx, jobs, _) {
              final posting = jobs.isPostingJob;
              return ElevatedButton(
                onPressed: (posting || _skill.isEmpty || _titleCtrl.text.trim().isEmpty || _workLocation == null || !_workLocation!.isValid) ? null : _postJob,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, disabledBackgroundColor: AppColors.divider, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: posting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Post Job →', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
              );
            },
          )),
          if (_workLocation == null || !_workLocation!.isValid)
            Padding(padding: const EdgeInsets.only(top: 6), child: Center(child: Text('Please select the exact work location.', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.red, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 24),
        ]))),
      ]),
    );
  }

  Future<void> _postJob() async {
    if (_workLocation == null || !_workLocation!.isValid) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isApproved || !auth.isHirer) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account not approved to post jobs'), backgroundColor: AppColors.red));
      return;
    }
    final jobsProvider = context.read<JobsProvider>();
    if (jobsProvider.isPostingJob) return; // provider-level lock

    final cat = kJobCategories.firstWhere((c) => c.id == _skill, orElse: () => kJobCategories.first);
    final jobId = await jobsProvider.postJob(Job(
      id: '', title: _titleCtrl.text.trim(), titleKn: _titleCtrl.text.trim(),
      skill: _skill, skillIcon: cat.emoji,
      hirer: auth.name, hirerId: auth.uid ?? '',
      district: _workLocation!.district, taluk: _workLocation!.taluk,
      village: _workLocation!.village,
      pay: _pay.toInt(), jobType: _jobType,
      urgent: _urgent, verified: false,
      description: _descCtrl.text.trim(),
      applicants: 0, match: 80, rating: 4.5,
      lat: _workLocation!.lat, lng: _workLocation!.lng, dist: 0,
      status: 'open', ago: 'now',
      workLocation: _workLocation,
    ));
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: jobId != null ? AppColors.green : AppColors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(
        jobId != null ? '✅ Job posted! Workers can see it now.' : '❌ Failed to post job. Try again.',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
    ));
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMed)));
  Widget _chip(String t) => Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)), child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textBody)));
}

// ── Find Workers Section ───────────────────────────────────────────────────
class _FindWorkersSection extends StatefulWidget {
  const _FindWorkersSection();
  @override
  State<_FindWorkersSection> createState() => _FindWorkersSectionState();
}

class _FindWorkersSectionState extends State<_FindWorkersSection> {
  bool _nearbyMode = true;
  String _selectedDistrict = '';
  Timer? _debounceTimer;
  String _selectedTaluk = '';
  String _selectedSkill = '';
  double _radiusKm = 10.0;
  List<WorkerSearchEntry> _allEntries = []; // Authoritative pool for current radius/area
  List<WorkerSearchEntry> _results = [];    // Filtered by selected skill (instant < 2ms)
  bool _isSearching = false;
  bool _hasSearched = false;
  String _errorMsg = '';
  bool _hasMore = false;
  Object? _nextCursor; // DocumentSnapshot for pagination

  // ── Auto-load on screen open ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // Pre-populate district from hirer's registered profile so "By Area" mode
    // works immediately without the hirer having to pick a district manually.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final hirerDistrict = auth.currentUser?.district ?? '';
      if (hirerDistrict.isNotEmpty && _selectedDistrict.isEmpty) {
        setState(() => _selectedDistrict = hirerDistrict);
      }
      _autoLoad();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Initial load: try GPS nearby. If GPS denied/unavailable, load all workers
  /// sorted by rating in the hirer's own district (no geo filter).
  Future<void> _autoLoad() async {
    if (!mounted || _isSearching) return;
    setState(() { _isSearching = true; _errorMsg = ''; });

    try {
      // Attempt GPS
      final hirerPos = await WorkerDiscoveryService.instance.getHirerPosition();
      if (!mounted) return;

      if (hirerPos != null) {
        // GPS available → nearby search
        _nearbyMode = true;
        final sessionId = WorkerDiscoveryService.instance.newSessionId();
        final result = await WorkerDiscoveryService.instance.search(WorkerSearchRequest(
          mode: WorkerSearchMode.nearbyGps,
          sessionId: sessionId,
          hirerPosition: hirerPos,
          skillId: '', // Fetch all skills to cache pool for instant filtering
          radiusKm: _radiusKm,
          limit: 30,
        ));
        if (!mounted) return;
        setState(() {
          _isSearching = false;
          _hasSearched = true;
          _allEntries = result.workers;
          _applySkillFilter();
          _hasMore = result.hasMore;
          _nextCursor = result.nextCursor;
          if (result.state == WorkerSearchState.error) {
            _errorMsg = result.errorMessage;
          }
        });
      } else {
        // GPS unavailable → load workers from hirer's own registered district
        // via manualArea search (all skills, sorted by rating)
        _nearbyMode = false;
        final auth = context.read<AuthProvider>();
        final hirerDistrict = auth.currentUser?.district ?? '';

        if (hirerDistrict.isNotEmpty) {
          // Use manualArea search for hirer's district
          _selectedDistrict = hirerDistrict;
          final sessionId = WorkerDiscoveryService.instance.newSessionId();
          final result = await WorkerDiscoveryService.instance.search(WorkerSearchRequest(
            mode: WorkerSearchMode.manualArea,
            sessionId: sessionId,
            district: hirerDistrict,
            skillId: '',
            limit: 30,
          ));
          if (!mounted) return;
          setState(() {
            _isSearching = false;
            _hasSearched = true;
            _allEntries = result.workers;
            _applySkillFilter();
            _hasMore = result.hasMore;
            _nextCursor = result.nextCursor;
            _errorMsg = '';
          });
        } else {
          // Hirer has no district set — fetch top-rated workers statewide
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'worker')
              .where('accountStatus', isEqualTo: 'approved')
              .where('isAvailable', isEqualTo: true)
              .limit(30)
              .get();
          if (!mounted) return;
          final profiles = snap.docs
              .map((d) => UserProfile.fromMap(d.id, d.data()))
              .toList();
          profiles.sort((a, b) => b.rating.compareTo(a.rating));
          setState(() {
            _isSearching = false;
            _hasSearched = true;
            _allEntries = profiles.map((p) => WorkerSearchEntry(profile: p, etaNote: '')).toList();
            _applySkillFilter();
            _hasMore = false;
            _errorMsg = '';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _isSearching = false; _errorMsg = ''; });
    }
  }

  Future<void> _search({bool loadMore = false}) async {
    if (_isSearching) return;
    if (!loadMore) {
      setState(() { _results = []; _hasSearched = false; _errorMsg = ''; _nextCursor = null; });
    }
    setState(() => _isSearching = true);
    try {
      LatLng? hirerPos;
      WorkerSearchMode mode;
      if (_nearbyMode) {
        hirerPos = await WorkerDiscoveryService.instance.getHirerPosition();
        if (hirerPos == null) {
          if (mounted) setState(() { _isSearching = false; _errorMsg = 'GPS unavailable. Switch to By Area mode.'; });
          return;
        }
        mode = WorkerSearchMode.nearbyGps;
      } else {
        if (_selectedDistrict.isEmpty) {
          if (mounted) setState(() { _isSearching = false; _errorMsg = 'Please select a district.'; });
          return;
        }
        mode = WorkerSearchMode.manualArea;
      }

      final sessionId = WorkerDiscoveryService.instance.newSessionId();
      final result = await WorkerDiscoveryService.instance.search(WorkerSearchRequest(
        mode: mode,
        sessionId: sessionId,
        hirerPosition: hirerPos,
        district: _selectedDistrict,
        taluk: _selectedTaluk,
        skillId: '', // Fetch full pool for area/radius so chip filtering is instant
        radiusKm: _radiusKm,
        limit: 30,
        cursor: loadMore ? _nextCursor : null,
      ));

      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _hasSearched = true;
        _hasMore = result.hasMore;
        _nextCursor = result.nextCursor;
        _errorMsg = result.state == WorkerSearchState.error ? result.errorMessage : '';
        if (loadMore) {
          _allEntries = [..._allEntries, ...result.workers];
        } else {
          _allEntries = result.workers;
        }
        _applySkillFilter();
        if (result.state == WorkerSearchState.locationUnavailable) {
          _errorMsg = 'GPS unavailable. Please switch to By Area mode.';
        }
      });
    } catch (e) {
      if (mounted) setState(() { _isSearching = false; _errorMsg = 'Search failed. Please try again.'; });
    }
  }

  /// Debounced search — waits 300ms after last event before firing.
  /// Prevents Firestore reads on every chip tap or radius change.
  void _debouncedSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _search();
    });
  }

  void _applySkillFilter() {
    if (_selectedSkill.isEmpty) {
      _results = List.from(_allEntries);
    } else {
      _results = _allEntries.where((w) => w.profile.skills.contains(_selectedSkill)).toList();
    }
  }

  /// Called when a skill chip is tapped — filters instantly in memory (< 2ms).
  void _onSkillTap(String skillId) {
    setState(() {
      _selectedSkill = skillId;
      _applySkillFilter();
    });
    if (_allEntries.isEmpty) {
      _debouncedSearch();
    }
  }

  /// Called when mode toggle changes — re-searches immediately.
  void _onModeChange(bool nearby) {
    setState(() {
      _nearbyMode = nearby;
      _allEntries = [];
      _results = [];
      _hasSearched = false;
      _errorMsg = '';
    });
    if (nearby) {
      // Switching to Nearby — run GPS search
      _debouncedSearch();
    } else {
      // Switching to By Area — auto-search if district already pre-populated
      if (_selectedDistrict.isNotEmpty) {
        _debouncedSearch();
      }
    }
  }

  /// Called when radius chip changes — re-searches immediately.
  void _onRadiusChange(double km) {
    setState(() {
      _radiusKm = km;
      _allEntries = [];
    });
    _debouncedSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with result count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Find Workers', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textHead)),
                const Spacer(),
                if (_results.isNotEmpty)
                  Text('${_results.length} found', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Mode Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _onModeChange(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _nearbyMode ? AppColors.primaryPale : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _nearbyMode ? AppColors.primary : AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text('📍 Nearby', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: _nearbyMode ? AppColors.primary : AppColors.textLight)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _onModeChange(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_nearbyMode ? AppColors.primaryPale : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: !_nearbyMode ? AppColors.primary : AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text('🔍 By Area', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: !_nearbyMode ? AppColors.primary : AppColors.textLight)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Area filters (By Area mode)
          if (!_nearbyMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDistrict.isEmpty ? null : _selectedDistrict,
                    hint: Text('Select District / ಜಿಲ್ಲೆ', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: KarnatakaLocation.allDistricts.map((d) => DropdownMenuItem(value: d, child: Text(d, style: GoogleFonts.plusJakartaSans(fontSize: 13)))).toList(),
                    onChanged: (val) {
                      setState(() { _selectedDistrict = val ?? ''; _selectedTaluk = ''; });
                      if (val != null && val.isNotEmpty) {
                        _debouncedSearch();
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTaluk.isEmpty ? null : _selectedTaluk,
                    hint: Text('Select Taluk / ತಾಲ್ಲೂಕು (Optional)', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: KarnatakaLocation.taluksForDistrict(_selectedDistrict).map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 13)))).toList(),
                    onChanged: (val) {
                      setState(() => _selectedTaluk = val ?? '');
                      Future.microtask(() => _search());
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

          // Radius chips (Nearby mode)
          if (_nearbyMode) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text('Radius:', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    ...[5.0, 10.0, 20.0, 50.0, 100.0].map((km) {
                      final sel = _radiusKm == km;
                      return GestureDetector(
                        onTap: () => _onRadiusChange(km),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.primaryPale : AppColors.surface2,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1),
                          ),
                          child: Text('${km.toInt()} km', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: sel ? AppColors.primary : AppColors.textBody)),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Skill chips — tapping immediately re-searches
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _skillChip('', 'All Skills'),
                ...kJobCategories.map((c) => _skillChip(c.id, '${c.emoji} ${c.label}')),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Error message
          if (_errorMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                _errorMsg.contains('console.firebase') || _errorMsg.contains('requires an index')
                    ? 'Worker search is temporarily unavailable. Please try again.\nಕೆಲಸಗಾರರ ಹುಡುಕಾಟ ತಾತ್ಕಾಲಿಕವಾಗಿ ಲಭ್ಯವಿಲ್ಲ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.'
                    : _errorMsg,
                style: GoogleFonts.plusJakartaSans(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),

          // Refresh / Search button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: _isSearching ? null : () => _search(),
              icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
              label: Text(_hasSearched ? 'Refresh Results' : 'Search Workers',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Loading shimmer — shaped like WorkerCard
          if (_isSearching && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: List.generate(3, (i) => Shimmer.fromColors(
                  baseColor: AppColors.border,
                  highlightColor: AppColors.surface2,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(height: 14, width: 140, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
                        const SizedBox(height: 8),
                        Container(height: 10, width: 90, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Container(height: 22, width: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
                          const SizedBox(width: 8),
                          Container(height: 22, width: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
                        ]),
                      ])),
                    ]),
                  ),
                )),
              ),
            ),

          // Empty state
          if (_hasSearched && !_isSearching && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    const Text('🔍', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 10),
                    Text('No workers available', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                    const SizedBox(height: 4),
                    Text(
                      _nearbyMode
                          ? 'Try a larger radius or switch to By Area'
                          : 'Try a different district or skill',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          // Results
          if (_results.isNotEmpty)
            ..._results.asMap().entries.map((entry) => WorkerCard(
              worker: entry.value.profile,
              searchEntry: entry.value,
              index: entry.key,
              onMessage: () async {
                final auth = context.read<AuthProvider>();
                if (auth.uid == null) return;
                await ChatService.getOrCreate(
                  myUid: auth.uid!,
                  otherUid: entry.value.profile.uid,
                  jobId: 'direct_hire_${entry.value.profile.uid}',
                  myName: auth.name,
                  otherName: entry.value.profile.displayName,
                  jobTitle: 'Direct Hire Inquiry',
                );
                if (!context.mounted) return;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    workerName: entry.value.profile.displayName,
                    jobTitle: 'Direct Hire Inquiry',
                    otherUserId: entry.value.profile.uid,
                    jobId: 'direct_hire_${entry.value.profile.uid}',
                  )
                ));
              },
              onViewProfile: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WorkerProfileDetailScreen(
                      worker: entry.value.profile,
                      searchEntry: entry.value,
                    ),
                  ),
                );
              },
            )),

          // Load more
          if (_hasMore && !_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _search(loadMore: true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Load More Workers', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _skillChip(String id, String label) {
    final isSelected = _selectedSkill == id;
    return GestureDetector(
      onTap: () => _onSkillTap(id), // auto-searches on tap
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryPale : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 2 : 1),
        ),
        child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: isSelected ? AppColors.primary : AppColors.textBody)),
      ),
    );
  }
}

// ── Active Hirer Booking Card (Flipkart / Urban Company Style) ─────────────────
class _ActiveHirerBookingCard extends StatelessWidget {
  final String hirerId;
  const _ActiveHirerBookingCard({required this.hirerId});

  @override
  Widget build(BuildContext context) {
    if (hirerId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('hirerId', isEqualTo: hirerId)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final activeDocs = snap.data!.docs.where((d) {
          final s = (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          if (s == 'confirmed' ||
              s == 'tracking' ||
              s == 'arrived' ||
              s == 'working' ||
              s == 'completion_requested' ||
              s == 'completion_verified' ||
              s == 'disputed') {
            return true;
          }
          if (s == 'completed') {
            final completedAt = (d.data() as Map<String, dynamic>)['completedAt'] as Timestamp?;
            if (completedAt != null && DateTime.now().difference(completedAt.toDate()).inMinutes < 60) {
              return true;
            }
          }
          return false;
        }).toList();
        if (activeDocs.isEmpty) return const SizedBox.shrink();

        activeDocs.sort((a, b) {
          final aT = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final bT = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return bT.compareTo(aT);
        });

        final doc = activeDocs.first;
        final data = doc.data() as Map<String, dynamic>;
        final bm = {...data, 'bookingId': doc.id};
        final status = data['status'] as String? ?? 'confirmed';
        final workerName = data['workerName'] as String? ?? 'Worker';
        final jobTitle = data['jobTitle'] as String? ?? 'Job';

        final isDisputed = status == 'disputed';
        final isCompleted = status == 'completed';
        final isCompVer = status == 'completion_verified';
        final isCompReq = status == 'completion_requested';
        final isWorking = status == 'working';
        final isArrived = status == 'arrived';
        final isTracking = status == 'tracking';
        final isConfirmed = status == 'confirmed';

        final gradientColors = isDisputed
            ? [const Color(0xFFDC2626), const Color(0xFF991B1B)]
            : isCompleted
                ? [const Color(0xFF059669), const Color(0xFF047857)]
                : isCompVer
                    ? [const Color(0xFF16A34A), const Color(0xFF0D9488)]
                    : isCompReq
                        ? [const Color(0xFFD97706), const Color(0xFF16A34A)]
                        : isWorking
                            ? [const Color(0xFF0D9488), const Color(0xFF059669)]
                            : isArrived
                                ? [const Color(0xFF2563EB), const Color(0xFF4F46E5)]
                                : isTracking
                                    ? [const Color(0xFF4F46E5), const Color(0xFF7C3AED)]
                                    : [const Color(0xFF0F766E), const Color(0xFF1E3A8A)];

        final badgeText = isDisputed
            ? '⚠️ WORK DISPUTED'
            : isCompleted
                ? '🎉 JOB COMPLETED'
                : isCompVer
                    ? '⭐ WORK CONFIRMED — RATE WORKER'
                    : isCompReq
                        ? '⭐ WORK COMPLETED — CONFIRM & RATE'
                        : isWorking
                            ? '🔨 WORK IN PROGRESS'
                            : isArrived
                                ? '📍 WORKER ARRIVED'
                                : isTracking
                                    ? '🛰️ WORKER ON THE WAY'
                                    : isConfirmed
                                        ? '🎉 WORKER HIRED & CONFIRMED'
                                        : '✅ BOOKING ACTIVE';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeText,
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    isCompReq
                        ? Icons.stars_rounded
                        : isWorking
                            ? Icons.construction_rounded
                            : isArrived
                                ? Icons.pin_drop_rounded
                                : Icons.navigation_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                jobTitle,
                style: GoogleFonts.sora(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Worker: $workerName',
                style: GoogleFonts.sora(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
              ),
              if (isArrived) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pin_outlined, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('Worker is on site • Tap below to enter OTP',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (isCompVer) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkDetailScreen(bookingId: doc.id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.star_rounded, size: 20),
                    label: Text(
                      '⭐ Rate Worker & Submit Feedback',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF16A34A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (isCompleted) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 16),
                      const SizedBox(width: 6),
                      Text('Job Completed & Rated • ${(data['hirerRatingStars'] as num?)?.toStringAsFixed(1) ?? "5.0"} ⭐',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (isDisputed) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('Work completion disputed • Tap for details',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (isCompReq || isWorking) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final auth = context.read<AuthProvider>();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkCompletionScreen(
                            bookingId: doc.id,
                            workerId: (data['workerId'] as String?) ?? '',
                            hirerId: auth.uid ?? hirerId,
                            jobId: (data['jobId'] as String?) ?? '',
                            skillId: (data['skillId'] as String?) ?? 'general',
                            workerName: workerName,
                            jobTitle: jobTitle,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.star_rounded, size: 20),
                    label: Text(
                      isCompReq ? '⭐ Confirm Work & Rate Worker' : '⭐ Work Done? Confirm & Rate',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF16A34A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (isTracking || isArrived || isConfirmed) {
                          JourneyNavigator.openHirer(context, booking: bm);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkDetailScreen(bookingId: doc.id),
                            ),
                          );
                        }
                      },
                      icon: Icon(
                        (isCompleted || isCompVer)
                            ? Icons.verified_rounded
                            : isDisputed
                                ? Icons.warning_amber_rounded
                                : isArrived
                                    ? Icons.pin_drop_rounded
                                    : (isTracking || isConfirmed)
                                        ? Icons.location_searching
                                        : Icons.visibility_rounded,
                        size: 16,
                      ),
                      label: Text(
                        isCompleted
                            ? 'Completed Details 🎉'
                            : isCompVer
                                ? 'Review & Details ⭐'
                                : isDisputed
                                    ? 'Dispute Details ⚠️'
                                    : isArrived
                                        ? 'Share OTP 📍'
                                        : (isTracking || isConfirmed)
                                            ? 'Track Worker 🛰️'
                                            : 'Work Details →',
                        style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: gradientColors.first,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkDetailScreen(bookingId: doc.id),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        'Details →',
                        style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}


