import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/user_profile.dart';
import '../../services/worker_availability_service.dart';
import '../../core/navigation/app_transitions.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../core/constants/karnataka_locations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/jobs_provider.dart';
import '../../widgets/job_card.dart';
import '../../widgets/booking/pending_direct_booking_card_list.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../tracking/journey_navigator.dart';
import '../chat/conversations_screen.dart';
import '../jobs/work_detail_screen.dart';
import '../../services/navigation/external_navigation_service.dart';
import '../../features/tracking/presentation/widgets/worker_otp_verification_sheet.dart';

class WorkerDashboard extends StatefulWidget {
  final Function(int)? onVoiceNavigate;
  const WorkerDashboard({super.key, this.onVoiceNavigate});
  @override State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String get _timeGreeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'ಶುಭ ಬೆಳಿಗ್ಗೆ'; // Good morning
    if (hour < 17) return 'ಶುಭ ಮಧ್ಯಾಹ್ನ'; // Good afternoon
    return 'ಶುಭ ಸಂಜೆ';                    // Good evening
  }
  final _searchCtrl = TextEditingController();
  String _selectedDistrict = '';

  @override
  void initState() {
    super.initState();
    // JobsProvider._authSub is the primary stream starter.
    // This addPostFrameCallback is a safety net — the guard inside
    // startListening() prevents double-subscription.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<JobsProvider>().startListening();
    });
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthProvider>();
    final jobs = context.watch<JobsProvider>();
    final filtered = jobs.filteredJobs;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        strokeWidth: 3,
        displacement: 64,
        onRefresh: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          await context.read<JobsProvider>().loadJobs();
          if (!mounted || messenger == null) return;
          messenger.showSnackBar(
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
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
          // ── Sticky App Bar ─────────────────────────────────
          SliverAppBar(
            pinned: true, floating: true, snap: false,
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0, expandedHeight: 60,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: SafeArea(child: Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _timeGreeting,
                        style: GoogleFonts.notoSansKannada(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        auth.currentUser?.displayName.split(' ').first ?? 'Worker',
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )),
                  GestureDetector(
                    onTap: () => Navigator.push(context, slideRightRoute(const ConversationsScreen())),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.primaryPale, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    // B01 FIX: Wire dead notifications bell → ConversationsScreen hub
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const ConversationsScreen(),
                      ));
                    },
                    child: Container(width: 40, height: 40, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryFire]), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 20)),
                  ),
                ])),
              ),
            ),
          ),

          // ── Search Bar ─────────────────────────────────────
          SliverToBoxAdapter(child: Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Expanded(child: Container(
                height: 44,
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: AppColors.textFaint, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => context.read<JobsProvider>().setSearch(v),
                    decoration: InputDecoration(
                      hintText: 'Search jobs, skills... / ಕೆಲಸ ಹುಡುಕಿ',
                      hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textFaint),
                      border: InputBorder.none, isDense: true,
                    ),
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead, fontWeight: FontWeight.w600),
                  )),
                  if (_searchCtrl.text.isNotEmpty) GestureDetector(onTap: () { _searchCtrl.clear(); context.read<JobsProvider>().setSearch(''); }, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.close, size: 16, color: AppColors.textFaint))),
                ]),
              )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showFilterSheet,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: jobs.filter.isActive ? AppColors.primary : AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: jobs.filter.isActive ? AppColors.primary : AppColors.border),
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    Icon(Icons.tune_rounded, color: jobs.filter.isActive ? Colors.white : AppColors.textMed, size: 20),
                    if (jobs.filter.activeCount > 0) Positioned(top: 6, right: 6, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                  ]),
                ),
              ),
            ]),
          )),

          // ── District + Taluk Dropdowns ──────────────────────
          SliverToBoxAdapter(child: Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Expanded(child: _dropdown(
                hint: '📍 District / ಜಿಲ್ಲೆ',
                value: jobs.filter.district.isEmpty ? null : jobs.filter.district,
                items: KarnatakaLocation.allDistricts,
                onChanged: (v) { context.read<JobsProvider>().setDistrict(v ?? ''); setState(() { _selectedDistrict = v ?? ''; }); },
              )),
              const SizedBox(width: 8),
              Expanded(child: _dropdown(
                hint: '📌 Taluk / ತಾಲ್ಲೂಕು',
                value: jobs.filter.taluk.isEmpty ? null : jobs.filter.taluk,
                items: _selectedDistrict.isNotEmpty ? KarnatakaLocation.taluksForDistrict(_selectedDistrict) : KarnatakaLocation.taluksForDistrict(jobs.filter.district),
                onChanged: (v) => context.read<JobsProvider>().setTaluk(v ?? ''),
                enabled: _selectedDistrict.isNotEmpty || jobs.filter.district.isNotEmpty,
              )),
            ]),
          )),

          // ── Active Filter Chips ─────────────────────────────
          if (jobs.filter.isActive) SliverToBoxAdapter(child: Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              Text('${filtered.length} results', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () { context.read<JobsProvider>().clearFilter(); _searchCtrl.clear(); setState(() { _selectedDistrict = ''; }); },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.redPale, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.red.withValues(alpha: 0.2))), child: Text('Clear All ✕', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.red))),
              ),
            ]),
          )),

          // ── Active Booking Card ─────────────────────────────
          SliverToBoxAdapter(child: _ActiveBookingCard(workerId: auth.currentUser?.uid ?? '')),

          // ── Pending Direct Booking Requests (Voice Discovery) ────────────
          SliverToBoxAdapter(
            child: PendingDirectBookingCardList(
              workerUid: auth.currentUser?.uid ?? '',
            ),
          ),

          // ── Availability Card (approved workers only) ────────────────────────
          if (auth.currentUser?.role == 'worker' &&
              auth.currentUser?.accountStatus == AccountStatus.approved)
            SliverToBoxAdapter(
              child: _AvailabilityCard(
                user: auth.currentUser!,
              ),
            ),

          // ── Skill Category Chips ────────────────────────────
          SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
              Text('ವರ್ಗಗಳು • Categories', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead)),
              const Spacer(),
              GestureDetector(onTap: () => context.read<JobsProvider>().setSkill(''), child: Text('All', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: jobs.filter.skill.isEmpty ? AppColors.primary : AppColors.textFaint, fontWeight: FontWeight.w700))),
            ])),
            const SizedBox(height: 8),
            SizedBox(height: 80, child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: kJobCategories.length,
              itemBuilder: (ctx, i) {
                final cat = kJobCategories[i];
                final sel = jobs.filter.skill == cat.id;
                return GestureDetector(
                  onTap: () => context.read<JobsProvider>().setSkill(cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primaryPale : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(cat.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(cat.labelKn, style: GoogleFonts.notoSansKannada(fontSize: 9, fontWeight: FontWeight.w700, color: sel ? AppColors.primary : AppColors.textBody)),
                    ]),
                  ).animate(delay: Duration(milliseconds: i * 30)).slideX(begin: 0.2, duration: 250.ms).fadeIn(duration: 250.ms),
                );
              },
            )),
          ])),

          // ── Sort Row ────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('🤖 AI Recommended Jobs', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textHead)),
                Text('${filtered.length} jobs • ${jobs.filter.district.isEmpty ? "All Karnataka" : jobs.filter.district}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
              ])),
              // Sort chips
              Row(children: SortMode.values.map((s) {
                final labels = {SortMode.match: '🤖', SortMode.distance: '📍', SortMode.pay: '💰', SortMode.rating: '⭐'};
                final sel = jobs.filter.sort == s;
                return GestureDetector(
                  onTap: () => context.read<JobsProvider>().setSort(s),
                  child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: sel ? AppColors.primary : AppColors.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: sel ? AppColors.primary : AppColors.border)), child: Text(labels[s]!, style: const TextStyle(fontSize: 14))),
                );
              }).toList()),
            ]),
          )),

          // ── Job Cards ────────────────────────────────────────────────────────
          if (jobs.isLoading)
            SliverList(delegate: SliverChildBuilderDelegate((ctx, i) => _shimmer(), childCount: 5))
          else if (jobs.error != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('⚠️', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('Could not load jobs', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead)),
              Text('ಕೆಲಸ ತೋರಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ', style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight)),
              const SizedBox(height: 8),
              Text('Check your internet connection and try again.',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
                textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // stopListening() sets _jobsSub = null, then startListening() creates fresh stream
                  final p = context.read<JobsProvider>();
                  p.stopListening();
                  p.startListening();
                },
                icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                label: Text('Retry', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ])))
          else if (filtered.isEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(40), child: Column(children: [
              const Text('🔍', style: TextStyle(fontSize: 50)),
              const SizedBox(height: 12),
              Text('No jobs found', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textHead)),
              Text(jobs.filter.isActive ? 'No jobs match these filters' : 'No open jobs right now', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textLight)),
              const SizedBox(height: 16),
              if (jobs.filter.isActive) ElevatedButton(onPressed: () { context.read<JobsProvider>().clearFilter(); _searchCtrl.clear(); setState(() { _selectedDistrict = ''; }); }, child: const Text('Clear Filters')),
            ])))
          else
            SliverList(delegate: SliverChildBuilderDelegate(
              (ctx, i) => RepaintBoundary(
                child: JobCard(
                  job: filtered[i],
                  index: i,
                  onApply: () {}, // handled internally by JobCard._handleApply()
                  alreadyApplied: jobs.appliedJobs.containsKey(filtered[i].id),
                ).animate(delay: Duration(milliseconds: i * 50)).slideY(begin: 0.12, duration: 350.ms).fadeIn(duration: 350.ms),
              ),
              childCount: filtered.length,
            )),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ]),
      ),
    );
  }

  Widget _dropdown({required String hint, required List<String> items, String? value, required Function(String?) onChanged, bool enabled = true}) => Container(
    height: 40,
    decoration: BoxDecoration(color: enabled ? AppColors.surface2 : AppColors.divider, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      value: value, hint: Text(hint, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textFaint), overflow: TextOverflow.ellipsis),
      isExpanded: true, icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textFaint),
      onChanged: enabled ? onChanged : null,
      style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHead),
      items: items.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
    )),
  );

  Widget _shimmer() => Shimmer.fromColors(
    baseColor: AppColors.border,
    highlightColor: AppColors.surface2,
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 14, width: 160, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 8),
            Container(height: 10, width: 110, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(height: 24, width: 52, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 4),
            Container(height: 10, width: 30, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
          ]),
        ]),
        const SizedBox(height: 12),
        Container(height: 1, color: Colors.white),
        const SizedBox(height: 10),
        Row(children: [
          Container(height: 22, width: 64, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
          const SizedBox(width: 6),
          Container(height: 22, width: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
          const Spacer(),
          Container(height: 34, width: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
        ]),
      ])),
    ),
  );
}

// ── Filter Bottom Sheet ─────────────────────────────────────────────────
class _FilterSheet extends StatefulWidget {
  @override State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late JobFilter _f;
  double _wage = 0;

  @override
  void initState() {
    super.initState();
    _f = context.read<JobsProvider>().filter;
    _wage = _f.minWage.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        Row(children: [
          Text('Filter Jobs', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textHead)),
          const Spacer(),
          TextButton(onPressed: () { setState(() { _f = const JobFilter(); _wage = 0; }); }, child: Text('Reset', style: GoogleFonts.plusJakartaSans(color: AppColors.red, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 16),
        Text('Minimum Wage: ₹${_wage.toInt()}/day', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead)),
        Slider(value: _wage, min: 0, max: 1500, divisions: 30, activeColor: AppColors.primary, onChanged: (v) => setState(() => _wage = v)),
        const SizedBox(height: 8),
        Row(children: [
          _toggle('🚨 Urgent Only', _f.urgentOnly, (v) => setState(() => _f = _f.copyWith(urgentOnly: v))),
          const SizedBox(width: 10),
          _toggle('✅ Verified Only', _f.verifiedOnly, (v) => setState(() => _f = _f.copyWith(verifiedOnly: v))),
        ]),
        const SizedBox(height: 8),
        Text('Job Type', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMed)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: ['Daily Wage', 'Weekly Contract', 'Project Based', 'Full-time', 'Monthly Contract'].map((t) {
          final sel = _f.jobType == t;
          return GestureDetector(onTap: () => setState(() => _f = _f.copyWith(jobType: sel ? '' : t)), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: sel ? AppColors.primaryPale : AppColors.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1)), child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? AppColors.primary : AppColors.textBody))));
        }).toList()),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
          onPressed: () {
            context.read<JobsProvider>().updateFilter(_f.copyWith(minWage: _wage.toInt()));
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: Text('Apply Filters', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        )),
      ]),
    );
  }

  Widget _toggle(String label, bool val, Function(bool) onChanged) => Expanded(child: GestureDetector(onTap: () => onChanged(!val), child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10), decoration: BoxDecoration(color: val ? AppColors.primaryPale : AppColors.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: val ? AppColors.primary : AppColors.border, width: val ? 2 : 1)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(val ? Icons.check_circle : Icons.circle_outlined, size: 14, color: val ? AppColors.primary : AppColors.textFaint), const SizedBox(width: 5), Expanded(child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: val ? AppColors.primary : AppColors.textMed)))]))));
}


// ── Active Booking Card ───────────────────────────────────────────────────────
// Shows confirmed/tracking bookings to worker so they can open journey
// directly from the dashboard without navigating to Applications tab.
class _ActiveBookingCard extends StatelessWidget {
  final String workerId;
  const _ActiveBookingCard({required this.workerId});

  @override
  Widget build(BuildContext context) {
    if (workerId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      // Single-field query — requires no composite index.
      stream: FirebaseFirestore.instance.collection('bookings')
          .where('workerId', isEqualTo: workerId)
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

        // Sort locally by createdAt descending
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
        final bm   = {...data, 'bookingId': doc.id};
        final status = data['status'] as String? ?? 'confirmed';
        final isTracking = status == 'tracking';
        final isWorking = status == 'working';
        final isArrived = status == 'arrived';
        final isCompReq = status == 'completion_requested';
        final isCompVer = status == 'completion_verified';
        final isCompleted = status == 'completed';
        final isDisputed = status == 'disputed';

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
                                    ? [const Color(0xFF1D4ED8), const Color(0xFF7C3AED)]
                                    : [const Color(0xFF065F46), const Color(0xFF0F766E)];

        final badgeText = isDisputed
            ? '⚠️ WORK DISPUTED'
            : isCompleted
                ? '🎉 JOB COMPLETED'
                : isCompVer
                    ? '⭐ WORK CONFIRMED'
                    : isCompReq
                        ? '⏳ COMPLETION REQUESTED'
                        : isWorking
                            ? '🔨 WORK IN PROGRESS'
                            : isArrived
                                ? '📍 ARRIVED AT SITE'
                                : isTracking
                                    ? '🔴 LIVE JOURNEY'
                                    : '✅ CONFIRMED BOOKING';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                child: Text(badgeText,
                  style: GoogleFonts.sora(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
              const Spacer(),
              Icon(
                isWorking ? Icons.construction_rounded : Icons.navigation_rounded,
                color: Colors.white,
                size: 20,
              ),
            ]),
            const SizedBox(height: 10),
            Text(data['jobTitle'] as String? ?? 'Booking', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Hirer: ${data['hirerName'] as String? ?? 'Confirmed hirer'}',
              style: GoogleFonts.sora(color: Colors.white70, fontSize: 13)),
            if (status == 'confirmed') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withAlpha(70)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.celebration_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'YOU ARE HIRED! Tap below to start your journey.',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isArrived) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('DOORSTEP: ASK HIRER FOR CODE • ಆಗಮನ ಕೋಡ್ ಕೇಳಿ',
                        style: GoogleFonts.sora(color: const Color(0xFFD1FAE5), fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
            if (isWorking) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Text('Work in progress • Active on site',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            if (isCompVer) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded, color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Text('Work Mutually Confirmed • Awaiting Hirer Review ⏳',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            if (isCompleted) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                    const SizedBox(width: 6),
                    Text('Completed & Rated • ${(data['hirerRatingStars'] as num?)?.toStringAsFixed(1) ?? "5.0"} ⭐',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            if (isDisputed) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Text('Completion disputed • Tap for details',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (isWorking || isCompReq || isCompVer || isCompleted || isDisputed) {
                      Navigator.push(
                        context,
                        fadeScaleRoute(WorkDetailScreen(bookingId: doc.id)),
                      );
                    } else if (isArrived) {
                      WorkerOtpVerificationSheet.show(
                        context,
                        bookingId: doc.id,
                        hirerName: data['hirerName'] as String? ?? 'Hirer',
                        jobTitle: data['jobTitle'] as String? ?? 'Service Job',
                      );
                    } else {
                      JourneyNavigator.openWorker(context, booking: bm, workerId: workerId);
                    }
                  },
                  icon: Icon(
                    (isCompleted || isCompVer)
                        ? Icons.verified_rounded
                        : isDisputed
                            ? Icons.warning_amber_rounded
                            : isWorking
                                ? Icons.task_alt_rounded
                                : isTracking
                                    ? Icons.navigation_rounded
                                    : isArrived
                                        ? Icons.vpn_key_rounded
                                        : Icons.navigation_rounded,
                    size: 17,
                  ),
                  label: Text(
                    isCompleted
                        ? 'View Job 🎉'
                        : isCompVer
                            ? 'Awaiting Review ⏳'
                            : isDisputed
                                ? 'Dispute Details ⚠️'
                                : isWorking
                                    ? 'Complete Work 🔨'
                                    : isCompReq
                                        ? 'Details ⏳'
                                        : isArrived
                                            ? 'Enter OTP 🔑'
                                            : isTracking
                                                ? 'Resume Nav'
                                                : 'Start Journey 🧭',
                    style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: gradientColors.first,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (isArrived) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      JourneyNavigator.openWorker(context, booking: bm, workerId: workerId);
                    },
                    icon: const Icon(Icons.navigation_rounded, size: 16, color: Colors.white),
                    label: Text(
                      'Journey 🧭',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 11, color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ] else if (isTracking || (!isWorking && !isCompReq)) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ExternalNavigationService.instance.openGoogleMapsForBooking(
                        context,
                        currentWorkerId: workerId,
                        bookingData: bm,
                        expectedJobId: data['jobId'] as String?,
                      );
                    },
                    icon: const Icon(Icons.map_rounded, size: 16, color: Colors.white),
                    label: Text(
                      'Maps 🗺️',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 11, color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    fadeScaleRoute(WorkDetailScreen(bookingId: doc.id)),
                  );
                },
                tooltip: 'Work Details',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(30),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.all(10),
                ),
                icon: const Icon(Icons.info_outline_rounded, size: 18),
              ),
            ]),
          ]),
        );
      },
    );
  }
}


// ── Worker Availability Card ─────────────────────────────────────────────────
// Shows current availability and lets approved workers toggle Available Now.
// Only visible to approved workers. Hidden for hirers and non-approved workers.
class _AvailabilityCard extends StatefulWidget {
  final UserProfile user;
  const _AvailabilityCard({required this.user});
  @override
  State<_AvailabilityCard> createState() => _AvailabilityCardState();
}

class _AvailabilityCardState extends State<_AvailabilityCard> {
  bool _loading = false;
  int _serviceRadius = 15; // km

  @override
  Widget build(BuildContext context) {
    final isAvailable = widget.user.isAvailable;
    final updatedAt = widget.user.discoveryUpdatedAt;
    final freshness = WorkerAvailabilityService.checkFreshness(updatedAt);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAvailable
              ? [const Color(0xFF059669), const Color(0xFF0F766E)]
              : [const Color(0xFF6B7280), const Color(0xFF4B5563)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(40), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(isAvailable ? Icons.location_on : Icons.location_off, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAvailable ? 'Available for Nearby Work' : 'Not Available',
                        style: GoogleFonts.sora(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (isAvailable && updatedAt != null)
                        Text(
                          _freshnessLabel(freshness, updatedAt),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        )
                      else if (!isAvailable)
                        Text(
                          'Turn on to let hirers find you nearby',
                          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                _loading
                    ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Switch(
                        value: isAvailable,
                        onChanged: (val) => _toggle(val),
                        activeThumbColor: Colors.white,
                        activeTrackColor: Colors.white.withAlpha(80),
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.white.withAlpha(50),
                      ),
              ],
            ),
            // Service radius chips (only when about to enable)
            if (!isAvailable) ...[
              const SizedBox(height: 12),
              Text('Service radius:', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [5, 10, 15, 20, 30].map((km) {
                  final sel = _serviceRadius == km;
                  return GestureDetector(
                    onTap: () => setState(() => _serviceRadius = km),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? Colors.white : Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withAlpha(80)),
                      ),
                      child: Text(
                        '$km km',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, fontWeight: FontWeight.w800,
                          color: sel ? AppColors.green : Colors.white,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(bool val) async {
    final uid = widget.user.uid;
    if (uid.isEmpty) return;
    setState(() => _loading = true);
    try {
      if (val) {
        final result = await WorkerAvailabilityService.instance.setAvailable(
          uid: uid, serviceRadiusKm: _serviceRadius,
        );
        if (!result.success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.errorMessage ?? 'Could not enable availability'),
            backgroundColor: AppColors.red,
          ));
        }
      } else {
        await WorkerAvailabilityService.instance.setUnavailable(uid);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _freshnessLabel(LocationFreshness f, DateTime updatedAt) {
    final age = DateTime.now().difference(updatedAt);
    final minAgo = age.inMinutes;
    switch (f) {
      case LocationFreshness.fresh:
        return '🟢 Location fresh • ${minAgo < 1 ? "just now" : "$minAgo min ago"}';
      case LocationFreshness.recent:
        return '🟡 Location updated $minAgo min ago';
      case LocationFreshness.stale:
        return '🔴 Location stale • please re-enable';
      case LocationFreshness.unknown:
        return '📍 Enabling will set your location';
    }
  }
}
