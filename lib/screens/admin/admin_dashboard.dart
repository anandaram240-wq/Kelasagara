import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/worker_registration_service.dart';
import '../../services/credential_service.dart';
import '../../models/worker_registration.dart';
import '../../models/credential_record.dart';
import 'assessment_review_screen.dart';
import 'credential_review_screen.dart';

/// Admin Dashboard — only visible to users with role == 'admin'
/// Admin bootstrap: manually set role: 'admin' in Firestore for your UID
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Double-check role (Security Rules also block on backend)
    if (!auth.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Access denied — Admin only')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Admin Panel', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          Text('ಕೆಲಸಗಾರ Management', style: GoogleFonts.notoSansKannada(fontSize: 10, color: Colors.white70)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => auth.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Pending', icon: Icon(Icons.pending_actions, size: 16)),
            Tab(text: 'All Users', icon: Icon(Icons.people, size: 16)),
            Tab(text: 'Jobs', icon: Icon(Icons.work, size: 16)),
            Tab(text: 'Assessments', icon: Icon(Icons.verified_user, size: 16)),
            Tab(text: 'Verifications', icon: Icon(Icons.fact_check, size: 16)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _PendingUsersTab(db: _db),
          _AllUsersTab(db: _db),
          _JobsTab(db: _db),
          const _AssessmentsTab(),
          const _VerificationsTab(),
        ],
      ),
    );
  }
}

// ── Pending Review Users Tab ─────────────────────────────────────────────────
class _PendingUsersTab extends StatelessWidget {
  final FirebaseFirestore db;
  const _PendingUsersTab({required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('users')
          .where('accountStatus', isEqualTo: 'pending_review')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('✅', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('No pending reviews!', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.green)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) => _UserCard(doc: docs[i], db: db)
              .animate(delay: Duration(milliseconds: i * 60))
              .slideY(begin: 0.1, duration: 300.ms).fadeIn(),
        );
      },
    );
  }
}

// ── User Card for Approval ────────────────────────────────────────────────────
class _UserCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final FirebaseFirestore db;
  const _UserCard({required this.doc, required this.db});
  @override State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  bool _processing = false;

  Future<void> _approve() async {
    setState(() => _processing = true);
    final adminUid = fb_auth.FirebaseAuth.instance.currentUser?.uid ?? 'unknown_admin';
    try {
      await widget.db.collection('users').doc(widget.doc.id).update({
        'accountStatus': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': 'admin', // In production: use actual admin UID
      });
      // Write audit log
      await widget.db.collection('auditLogs').add({
        'action': 'approve_user',
        'targetUid': widget.doc.id,
        'targetName': widget.doc['name'] ?? '',
        'performedBy': 'admin',
        'timestamp': FieldValue.serverTimestamp(),
        'previousStatus': 'pending_review',
        'newStatus': 'approved',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.green, behavior: SnackBarBehavior.floating,
            content: Text('✅ ${widget.doc['name']} approved!', style: GoogleFonts.sora(fontWeight: FontWeight.w700))),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.red, content: Text('Error: $e')),
      );
    }
    if (mounted) setState(() => _processing = false);
  }

  Future<void> _reject(String reason) async {
    setState(() => _processing = true);
    try {
      await widget.db.collection('users').doc(widget.doc.id).update({
        'accountStatus': 'rejected',
        'rejectionReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': 'admin',
      });
      await widget.db.collection('auditLogs').add({
        'action': 'reject_user',
        'targetUid': widget.doc.id,
        'reason': reason,
        'performedBy': 'admin',
        'timestamp': FieldValue.serverTimestamp(),
        'previousStatus': 'pending_review',
        'newStatus': 'rejected',
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.red, content: Text('Error: $e')),
      );
    }
    if (mounted) setState(() => _processing = false);
  }

  void _showRejectDialog() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('Reject ${widget.doc['name']}', style: GoogleFonts.sora(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(hintText: 'Reason for rejection...'),
        maxLines: 3,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); _reject(ctrl.text); },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
          child: const Text('Reject'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final role = d['role'] ?? 'worker';
    final facePhoto = d['facePhotoUrl'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          // Face photo
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryPale,
              border: Border.all(color: AppColors.primaryBorder, width: 2)),
            child: facePhoto.isNotEmpty
                ? ClipOval(child: CachedNetworkImage(
                    imageUrl: facePhoto,
                    fit: BoxFit.cover,
                    memCacheWidth: 112,
                    memCacheHeight: 112,
                    errorWidget: (_, __, ___) => const Icon(Icons.person, color: AppColors.primary),
                    placeholder: (_, __) => const Icon(Icons.person, color: AppColors.primaryPale),
                  ))
                : const Icon(Icons.person, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['name'] ?? 'Unknown', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textHead)),
            Text('${role.toUpperCase()} • ${d['district'] ?? 'Unknown district'}',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
            Text(d['phone'] ?? d['email'] ?? '',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textFaint)),
          ])),
          // Face verified badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (d['faceVerified'] == true) ? AppColors.green.withValues(alpha: 0.1) : AppColors.redPale,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              (d['faceVerified'] == true) ? '✅ Face Done' : '❌ No Face',
              style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w800,
                color: (d['faceVerified'] == true) ? AppColors.green : AppColors.red),
            ),
          ),
        ])),

        // Skills
        if ((d['skills'] as List?)?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Wrap(spacing: 6, children: (d['skills'] as List)
                .map((s) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
                  child: Text(s.toString(), style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textMed)),
                ))
                .toList()),
          ),

        // Actions
        Container(
          height: 1, color: AppColors.divider,
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: _processing
              ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)))
              : Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _showRejectDialog,
                    icon: const Icon(Icons.close, size: 14),
                    label: Text('Reject', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton.icon(
                    onPressed: _approve,
                    icon: const Icon(Icons.check, size: 14, color: Colors.white),
                    label: Text('Approve', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  )),
                ]),
        ),
      ]),
    );
  }
}

// ── All Users Tab ─────────────────────────────────────────────────────────────
class _AllUsersTab extends StatelessWidget {
  final FirebaseFirestore db;
  const _AllUsersTab({required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('users').limit(50).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        final docs = snap.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['accountStatus'] ?? 'unknown';
            final statusColor = switch (status) {
              'approved'       => AppColors.green,
              'pending_review' => AppColors.gold,
              'rejected'       => AppColors.red,
              'suspended'      => AppColors.red,
              _                => AppColors.textFaint,
            };
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primaryPale,
                  child: Text((d['name'] ?? 'U')[0].toUpperCase(),
                    style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d['name'] ?? 'Unknown', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                  Text('${(d['role'] ?? 'worker').toUpperCase()} • ${d['district'] ?? ''}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(status.toUpperCase().replaceAll('_', ' '),
                    style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w800, color: statusColor)),
                ),
              ]),
            );
          },
        );
      },
    );
  }
}

// ── Jobs Tab ──────────────────────────────────────────────────────────────────
class _JobsTab extends StatelessWidget {
  final FirebaseFirestore db;
  const _JobsTab({required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('jobs').limit(50).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No jobs posted yet'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Text('💼', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d['title'] ?? '', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                  Text('by ${d['hirerName'] ?? ''} • ${d['district'] ?? ''}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textLight)),
                  Text('₹${d['pay'] ?? 0}/day • ${d['applicants'] ?? 0} applicants',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.green)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primaryPale, borderRadius: BorderRadius.circular(8)),
                  child: Text((d['status'] ?? 'open').toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ),
              ]),
            );
          },
        );
      },
    );
  }
}

// ── Assessments Tab ────────────────────────────────────────────────
class _AssessmentsTab extends StatelessWidget {
  const _AssessmentsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
        .collection('skillAssessments')
        .where('status', whereIn: ['submitted', 'under_review'])
        .snapshots(),
      builder: (ctx, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📋', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                count == 0
                  ? 'No pending assessments'
                  : '$count assessment${count == 1 ? '' : 's'} pending review',
                style: GoogleFonts.sora(
                  color: AppColors.textHead, fontSize: 16,
                  fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AssessmentReviewScreen())),
                icon: const Icon(Icons.rate_review_rounded, color: Colors.white),
                label: Text('Open Review Panel',
                  style: GoogleFonts.sora(
                    color: Colors.white, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)))),
            ],
          ),
        );
      },
    );
  }
}


// ── Verifications Tab ──────────────────────────────────────────────────────────
class _VerificationsTab extends StatelessWidget {
  const _VerificationsTab();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: const Color(0xFF1E293B),
          child: const TabBar(
            indicatorColor: Color(0xFF6366F1),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(text: 'Registrations'),
              Tab(text: 'Credentials'),
            ],
          ),
        ),
        const Expanded(child: TabBarView(children: [
          _PendingRegistrationsTab(),
          _PendingCredentialsTab(),
        ])),
      ]),
    );
  }
}

class _PendingRegistrationsTab extends StatelessWidget {
  const _PendingRegistrationsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WorkerRegistration>>(
      stream: WorkerRegistrationService.instance.streamPendingRegistrations(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(child: Text('No pending registrations',
            style: GoogleFonts.sora(color: Colors.white54)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final r = list[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(r.registrationType.displayName,
                    style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withAlpha(40),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(r.status.displayLabel,
                      style: GoogleFonts.sora(color: const Color(0xFFFBBF24), fontSize: 10))),
                ]),
                const SizedBox(height: 6),
                Text('Ref: ${r.referenceNumber}', style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 12)),
                Text('Occupation: ${r.declaredOccupation}', style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 12)),
                Text('Worker: ${r.workerId}', style: GoogleFonts.sora(color: const Color(0xFF475569), fontSize: 11)),
                if (r.documentDownloadUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: Image.network(r.documentDownloadUrl!, height: 120, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox())),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  ElevatedButton(
                    onPressed: () async {
                      final adminId = context.read<AuthProvider>().currentUser?.uid ?? '';
                      await WorkerRegistrationService.instance.adminUpdateStatus(
                        workerId: r.workerId, newStatus: RegistrationStatus.verified,
                        adminId: adminId, reviewNotes: 'Source checked by admin');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('Verify', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final adminId = context.read<AuthProvider>().currentUser?.uid ?? '';
                      await WorkerRegistrationService.instance.adminUpdateStatus(
                        workerId: r.workerId, newStatus: RegistrationStatus.rejected,
                        adminId: adminId, rejectionReason: 'Document not verifiable');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('Reject', style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                ]),
              ]),
            );
          },
        );
      },
    );
  }
}

class _PendingCredentialsTab extends StatelessWidget {
  const _PendingCredentialsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CredentialRecord>>(
      stream: CredentialService.instance.streamPendingCredentials(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(child: Text('No pending credentials',
            style: GoogleFonts.sora(color: Colors.white54)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final c = list[i];
            return InkWell(
              onTap: () => Navigator.push(ctx,
                MaterialPageRoute(builder: (_) => CredentialReviewScreen(credential: c))),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(
                      c.credentialName.isEmpty ? c.credentialType.displayName : c.credentialName,
                      style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ]),
                  const SizedBox(height: 4),
                  Text('Issuer: ${c.issuer}', style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 12)),
                  Text('Cert No.: ${c.credentialNumber}', style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 12)),
                  Text('Skill: ${c.skillId} | Worker: ${c.workerId.substring(0, 8)}...',
                    style: GoogleFonts.sora(color: const Color(0xFF64748B), fontSize: 11)),
                  Text('Tap to review →', style: GoogleFonts.sora(color: const Color(0xFF6366F1), fontSize: 11)),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}
