import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/job_categories.dart';
import '../models/work_location.dart';

// ── Job Model ────────────────────────────────────────────────────────────────
class Job {
  final String id;
  final String title;
  final String titleKn;
  final String skill;
  final String skillIcon;
  final String hirer;
  final String hirerId;
  final String district;
  final String taluk;
  final String village;
  final int pay;
  final String jobType;
  final int applicants;
  final double match;
  final double rating;
  final double lat;
  final double lng;
  final double dist;
  final String status;
  final String ago;
  final bool urgent;
  final bool verified;
  final DateTime? createdAt;
  final String description;
  final WorkLocation? workLocation;
  final bool hasPrivateLocation;

  const Job({
    required this.id,
    required this.title,
    this.titleKn = '',
    required this.skill,
    this.skillIcon = '🔧',
    this.hirer = '',
    this.hirerId = '',
    required this.district,
    this.taluk = '',
    this.village = '',
    required this.pay,
    this.jobType = 'Daily Wage',
    this.applicants = 0,
    this.match = 80,
    this.rating = 4.0,
    this.lat = 0.0,
    this.lng = 0.0,
    this.dist = 0,
    this.status = 'open',
    this.ago = '',
    this.urgent = false,
    this.verified = false,
    this.createdAt,
    this.description = '',
    this.workLocation,
    this.hasPrivateLocation = false,
  });

  factory Job.fromFirestore(DocumentSnapshot doc) {
    return Job.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  factory Job.fromMap(String id, Map<String, dynamic> d) {
    final skill = (d['skill'] as String?) ?? '';
    final cat = kJobCategories.firstWhere(
      (c) => c.id == skill, orElse: () => kJobCategories.first,
    );
    final rawPostedAt = d['postedAt'] ?? d['createdAt'];
    DateTime? createdAt;
    if (rawPostedAt is Timestamp) {
      createdAt = rawPostedAt.toDate();
    } else if (rawPostedAt is String) {
      createdAt = DateTime.tryParse(rawPostedAt);
    } else if (rawPostedAt is DateTime) {
      createdAt = rawPostedAt;
    }

    WorkLocation? workLoc;
    try {
      final locMap = d['location'] as Map<String, dynamic>?;
      if (locMap != null) workLoc = WorkLocation.fromMap(locMap);
    } catch (_) {}

    return Job(
      id:          id,
      title:       (d['title']     as String?) ?? '',
      titleKn:     (d['titleKn']   as String?) ?? (d['title'] as String?) ?? '',
      skill:       skill,
      skillIcon:   cat.emoji,
      hirer:       (d['hirerName'] as String?) ?? (d['hirer'] as String?) ?? '',
      hirerId:     (d['hirerId']   as String?) ?? (d['hirerUid'] as String?) ?? (d['createdById'] as String?) ?? (d['createdBy'] as String?) ?? '',
      district:    (d['district']  as String?) ?? workLoc?.district ?? '',
      taluk:       (d['taluk']     as String?) ?? workLoc?.taluk    ?? '',
      village:     (d['village']   as String?) ?? workLoc?.village  ?? '',
      pay:         ((d['pay']        ?? 0)   as num).toInt(),
      jobType:     (d['jobType']   as String?) ?? 'Daily Wage',
      applicants:  ((d['applicants'] ?? 0)   as num).toInt(),
      match:       ((d['match']      ?? 80)  as num).toDouble(),
      rating:      ((d['rating']     ?? 4.0) as num).toDouble(),
      lat:         ((d['lat']        ?? 0.0) as num).toDouble(),
      lng:         ((d['lng']        ?? 0.0) as num).toDouble(),
      dist:        ((d['dist']       ?? 0)   as num).toDouble(),
      status:      (d['status']    as String?) ?? 'open',
      ago:         _timeAgo(createdAt),
      urgent:      (d['urgent']    as bool?)   ?? false,
      verified:    (d['verified']  as bool?)   ?? false,
      createdAt:   createdAt,
      description: (d['description'] as String?) ?? '',
      workLocation: workLoc,
      hasPrivateLocation: (d['hasPrivateLocation'] as bool?) ?? false,
    );
  }

  static String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Filters & Sort ────────────────────────────────────────────────────────────
enum SortMode { match, distance, pay, rating }

class JobFilter {
  final String search;
  final String district;
  final String taluk;
  final String skill;
  final String jobType;
  final int minWage;
  final double minRating;
  final bool urgentOnly;
  final bool verifiedOnly;
  final SortMode sort;

  const JobFilter({
    this.search = '', this.district = '', this.taluk = '',
    this.skill = '', this.jobType = '', this.minWage = 0,
    this.minRating = 0, this.urgentOnly = false,
    this.verifiedOnly = false, this.sort = SortMode.match,
  });

  JobFilter copyWith({
    String? search, String? district, String? taluk, String? skill,
    String? jobType, int? minWage, double? minRating,
    bool? urgentOnly, bool? verifiedOnly, SortMode? sort,
  }) => JobFilter(
    search: search ?? this.search, district: district ?? this.district,
    taluk: taluk ?? this.taluk, skill: skill ?? this.skill,
    jobType: jobType ?? this.jobType, minWage: minWage ?? this.minWage,
    minRating: minRating ?? this.minRating, urgentOnly: urgentOnly ?? this.urgentOnly,
    verifiedOnly: verifiedOnly ?? this.verifiedOnly, sort: sort ?? this.sort,
  );

  bool get isActive =>
    search.isNotEmpty || district.isNotEmpty || taluk.isNotEmpty ||
    skill.isNotEmpty || jobType.isNotEmpty || minWage > 0 ||
    minRating > 0 || urgentOnly || verifiedOnly;

  int get activeCount => [
    search.isNotEmpty, district.isNotEmpty, taluk.isNotEmpty,
    skill.isNotEmpty, jobType.isNotEmpty, minWage > 0,
    minRating > 0, urgentOnly, verifiedOnly,
  ].where((e) => e).length;
}

// ── JobsProvider ──────────────────────────────────────────────────────────────
class JobsProvider extends ChangeNotifier {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Worker feed (status=open, all hirers) ─────────────────────────────────
  List<Job> _allJobs = [];
  StreamSubscription<QuerySnapshot>? _jobsSub;

  // ── Hirer's own jobs (own hirerId, any status) ────────────────────────────
  List<Job> _hirerJobs = [];
  StreamSubscription<QuerySnapshot>? _hirerJobsSub;
  String? _hirerUid;

  // ── Worker's real-time applications stream ─────────────────────────────────
  StreamSubscription<QuerySnapshot>? _appliedJobsSub;

  // ── Auth state subscription (auto-cleanup on sign-out) ────────────────────
  late final StreamSubscription<User?> _authSub;

  JobFilter _filter    = const JobFilter();
  bool      _isLoading = true;  // ← start true: loading until first snapshot
  String?   _error;
  Map<String, String> _appliedJobs = {}; // jobId → applicationId

  JobFilter get filter    => _filter;
  bool      get isLoading => _isLoading;
  String?   get error     => _error;
  Map<String, String> get appliedJobs => _appliedJobs;

  List<Job> get hirerJobs  => _hirerJobs;
  List<Job> get postedJobs => _hirerJobs; // backward compat
  String?   get contextHirerId => _hirerUid;
  String?   get hirerUid => _hirerUid;

  // ── Constructor: listen to Firebase Auth state ────────────────────────────
  JobsProvider() {
    _authSub = _auth.authStateChanges().listen((user) {
      if (user == null) {
        // ── User signed out — tear everything down ──────────────────────────
        debugPrint('🔑 JobsProvider: signed out → stopping all streams');
        _jobsSub?.cancel();
        _jobsSub = null;
        _hirerJobsSub?.cancel();
        _hirerJobsSub = null;
        _appliedJobsSub?.cancel();
        _appliedJobsSub = null;
        _hirerUid = null;
        _allJobs  = [];
        _hirerJobs = [];
        _appliedJobs = {};
        _isLoading = true; // reset for next login
        _error = null;
        notifyListeners();
      } else {
        // ── User signed in — ensure streams are running ─────────────────────
        debugPrint('🔑 JobsProvider: signed in uid=${user.uid}');
        if (_jobsSub == null) {
          startListening();
        }
        startAppliedJobsStream(user.uid);
      }
    });
  }

  // ── Filtered + Sorted Job List (worker feed) ──────────────────────────────
  List<Job> get filteredJobs {
    var jobs = [..._allJobs];
    final f = _filter;
    final q = f.search.toLowerCase();

    if (q.isNotEmpty) {
      jobs = jobs.where((j) =>
        j.title.toLowerCase().contains(q) ||
        j.titleKn.contains(q) ||
        j.skill.toLowerCase().contains(q) ||
        j.hirer.toLowerCase().contains(q) ||
        j.district.toLowerCase().contains(q) ||
        j.taluk.toLowerCase().contains(q)
      ).toList();
    }
    if (f.district.isNotEmpty) {
      final fD = f.district.toLowerCase().trim();
      jobs = jobs.where((j) {
        final jD = j.district.toLowerCase().trim();
        return jD == fD || jD.contains(fD) || fD.contains(jD);
      }).toList();
    }
    if (f.taluk.isNotEmpty) {
      final fT = f.taluk.toLowerCase().trim();
      jobs = jobs.where((j) {
        final jT = j.taluk.toLowerCase().trim();
        return jT == fT || jT.contains(fT) || fT.contains(jT);
      }).toList();
    }
    if (f.skill.isNotEmpty) {
      final fS = f.skill.toLowerCase().trim();
      jobs = jobs.where((j) => j.skill.toLowerCase().trim() == fS).toList();
    }
    if (f.jobType.isNotEmpty)  jobs = jobs.where((j) => j.jobType == f.jobType).toList();
    if (f.minWage > 0)         jobs = jobs.where((j) => j.pay >= f.minWage).toList();
    if (f.minRating > 0)       jobs = jobs.where((j) => j.rating >= f.minRating).toList();
    if (f.urgentOnly)          jobs = jobs.where((j) => j.urgent).toList();
    if (f.verifiedOnly)        jobs = jobs.where((j) => j.verified).toList();

    switch (f.sort) {
      case SortMode.match:    jobs.sort((a, b) => b.match.compareTo(a.match));
      case SortMode.distance: jobs.sort((a, b) => a.dist.compareTo(b.dist));
      case SortMode.pay:      jobs.sort((a, b) => b.pay.compareTo(a.pay));
      case SortMode.rating:   jobs.sort((a, b) => b.rating.compareTo(a.rating));
    }

    debugPrint(
      '📊 filteredJobs: raw=${_allJobs.length} '
      'district="${f.district}" taluk="${f.taluk}" skill="${f.skill}" '
      '→ ${jobs.length} shown',
    );

    return jobs;
  }

  // ── Worker feed: real-time stream of open jobs ────────────────────────────
  //
  // KEY FIX: guard checks _jobsSub == null, NOT whether it was ever set.
  // On error, _jobsSub is set to null so this method can restart cleanly.
  // On sign-out, _authSub listener cancels and nullifies _jobsSub.
  //
  void startListening() {
    if (_jobsSub != null) {
      debugPrint('🔍 JobsProvider: startListening() — stream already active, skip');
      return;
    }

    debugPrint('🔍 JobsProvider: starting worker job stream (status=open)…');
    _isLoading = true;
    _error = null;
    notifyListeners();

    _jobsSub = _db
        .collection('jobs')
        .where('status', isEqualTo: 'open')
        .limit(150)
        .snapshots()
        .listen(
      (snap) {
        debugPrint('✅ JobsProvider: Firestore returned ${snap.docs.length} docs');

        final jobs = <Job>[];
        for (final doc in snap.docs) {
          try {
            jobs.add(Job.fromFirestore(doc));
          } catch (e) {
            // One bad doc must NOT kill the whole feed
            debugPrint('⚠️ JobsProvider: failed to parse doc ${doc.id}: $e');
          }
        }

        jobs.sort((a, b) {
          final aT = a.createdAt ?? DateTime(2000);
          final bT = b.createdAt ?? DateTime(2000);
          return bT.compareTo(aT);
        });

        _allJobs  = jobs;
        _isLoading = false;
        _error     = null;

        debugPrint(
          '✅ JobsProvider: _allJobs updated → ${_allJobs.length} jobs. '
          'district=${_filter.district.isEmpty ? "ALL" : _filter.district}',
        );

        notifyListeners();
      },
      onError: (e) {
        debugPrint('❌ JobsProvider: stream error: $e');
        _error     = 'Unable to load jobs. Please check your connection.';
        _isLoading = false;

        // ── KEY FIX: null _jobsSub so startListening() can restart ────────
        _jobsSub?.cancel();
        _jobsSub = null;

        notifyListeners();

        // Auto-retry after 5s if user is still signed in
        Future.delayed(const Duration(seconds: 5), () {
          if (_auth.currentUser != null && _jobsSub == null) {
            debugPrint('🔄 JobsProvider: auto-retry after stream error…');
            startListening();
          }
        });
      },
    );
  }

  Future<void> loadJobs() async => startListening(); // backward compat alias

  void stopListening() {
    debugPrint('🛑 JobsProvider: stopListening()');
    _jobsSub?.cancel();
    _jobsSub = null;
  }

  // ── Hirer feed: dedicated stream for hirer's OWN jobs ────────────────────
  void startHirerStream(String uid) {
    if (_hirerUid == uid && _hirerJobsSub != null) return;
    debugPrint('🔍 JobsProvider: starting hirer stream for uid=$uid');
    _hirerUid = uid;
    _hirerJobsSub?.cancel();

    _hirerJobsSub = _db
        .collection('jobs')
        .where('hirerId', isEqualTo: uid)
        .limit(100)
        .snapshots()
        .listen(
      (snap) {
        debugPrint('✅ JobsProvider: hirer stream → ${snap.docs.length} jobs');
        final jobs = <Job>[];
        for (final doc in snap.docs) {
          try { jobs.add(Job.fromFirestore(doc)); }
          catch (e) { debugPrint('⚠️ hirer doc parse: $e'); }
        }
        jobs.sort((a, b) {
          final aT = a.createdAt ?? DateTime(2000);
          final bT = b.createdAt ?? DateTime(2000);
          return bT.compareTo(aT);
        });
        _hirerJobs = jobs;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('❌ JobsProvider: hirer stream error: $e');
        _hirerJobsSub?.cancel();
        _hirerJobsSub = null;
      },
    );
  }

  void stopHirerStream() {
    _hirerJobsSub?.cancel();
    _hirerJobsSub = null;
    _hirerUid = null;
  }

  // Kept for backward compat — HirerDashboard calls startHirerStream()
  void setHirerContext(String hirerId) {
    if (_hirerUid != hirerId) _hirerUid = hirerId;
  }

  // ── Job posting submission lock (provider-level, survives widget rebuilds) ──
  String? _pendingPost;
  bool get isPostingJob => _pendingPost != null;

  String? _lastPostError;
  String? get lastPostError => _lastPostError;

  String? _lastApplyError;
  String? get lastApplyError => _lastApplyError;

  /// Post a new job to Firestore — location is REQUIRED.
  /// Two-Tier Location Disclosure:
  /// - Public job doc in `jobs`: General area only (District, Taluk, Village). NO exact lat/lng/address.
  /// - Private job doc in `jobPrivate`: Exact address, lat/lng, and site notes.
  /// Idempotent: provider-level lock prevents duplicate writes on rapid taps.
  Future<String?> postJob(Job job) async {
    final loc = job.workLocation;
    if (loc == null || !loc.isValid) {
      debugPrint('❌ postJob: workLocation is null or invalid');
      _lastPostError = 'Work location is required and must be valid';
      return null;
    }

    if (_pendingPost != null) {
      debugPrint('❌ postJob: already posting, skip');
      return null;
    }

    final token = '${job.hirerId}_${DateTime.now().millisecondsSinceEpoch}';
    _pendingPost = token;
    _lastPostError = null;
    notifyListeners();

    try {
      final jobDocRef = _db.collection('jobs').doc();
      final jobId = jobDocRef.id;
      final jobPrivateRef = _db.collection('jobPrivate').doc(jobId);

      final publicData = {
        'title':       job.title,
        'titleKn':     job.titleKn,
        'skill':       job.skill,
        'skillIcon':   job.skillIcon,
        'hirer':       job.hirer,
        'hirerName':   job.hirer,
        'hirerId':     job.hirerId,
        'district':    loc.district.isNotEmpty ? loc.district : job.district,
        'taluk':       loc.taluk.isNotEmpty    ? loc.taluk    : job.taluk,
        'village':     loc.village.isNotEmpty  ? loc.village  : job.village,
        'pay':         job.pay,
        'jobType':     job.jobType,
        'urgent':      job.urgent,
        'verified':    false,
        'status':      'open',
        'applicants':  0,
        'match':       80,
        'rating':      4.5,
        'dist':        0,
        'postedAt':    FieldValue.serverTimestamp(),
        'description': job.description,
        'hasPrivateLocation': true,
        '_token':      token,
      };

      final privateData = {
        'jobId':      jobId,
        'hirerId':    job.hirerId,
        'lat':        loc.lat,
        'lng':        loc.lng,
        'address':    loc.address,
        'district':   loc.district,
        'taluk':      loc.taluk,
        'village':    loc.village,
        'pincode':    loc.pincode,
        'createdAt':  FieldValue.serverTimestamp(),
      };

      debugPrint('📤 postJob: writing job & jobPrivate (Two-Tier Location) to Firestore…');
      try {
        final batch = _db.batch();
        batch.set(jobDocRef, publicData);
        batch.set(jobPrivateRef, privateData);
        await batch.commit();
        debugPrint('✅ postJob: SUCCESS (two-tier batch) jobId=$jobId');
        return jobId;
      } on FirebaseException catch (batchErr) {
        if (batchErr.code == 'permission-denied') {
          debugPrint('⚠️ postJob: batch permission-denied (${batchErr.message}), falling back to direct job write with location map…');
          final fallbackPublicData = Map<String, dynamic>.from(publicData);
          fallbackPublicData['location'] = loc.toMap();
          fallbackPublicData['lat'] = loc.lat;
          fallbackPublicData['lng'] = loc.lng;
          fallbackPublicData['address'] = loc.address;
          await jobDocRef.set(fallbackPublicData);

          try {
            await jobPrivateRef.set(privateData);
          } catch (pErr) {
            debugPrint('⚠️ postJob: non-fatal jobPrivate write error: $pErr');
          }

          debugPrint('✅ postJob: SUCCESS (fallback write) jobId=$jobId');
          return jobId;
        }
        rethrow;
      }
    } on FirebaseException catch (e) {
      debugPrint('❌ postJob FirebaseException: ${e.code} ${e.message}');
      _lastPostError = e.code == 'permission-denied'
          ? 'Permission denied: Please ensure your profile is complete as a Hirer.'
          : (e.message ?? e.code);
      return null;
    } catch (e) {
      debugPrint('❌ postJob: FAILED: $e');
      _lastPostError = e.toString();
      return null;
    } finally {
      _pendingPost = null;
      notifyListeners();
    }
  }

  /// Close a job (hirer action)
  Future<void> closeJob(String jobId) async {
    try {
      await _db.collection('jobs').doc(jobId).update({
        'status':   'closed',
        'closedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ closeJob: $jobId → closed');
    } catch (e) {
      debugPrint('❌ closeJob error: $e');
    }
  }

  // ── Apply to Job (real Firestore — deterministic ID prevents duplicates) ──
  Future<String?> applyToJob({
    required String jobId,
    required String workerId,
    required String workerName,
    required String hirerId,
    String workerPhoto = '',
    double workerRating = 0.0,
    int workerTotalJobs = 0,
    List<String> workerSkills = const [],
    bool workerVerified = false,
    String message   = '',
    String jobTitle  = '',
    String skill     = '',
    String hirerName = '',
    int    pay       = 0,
  }) async {
    _lastApplyError = null;

    // Fast path: already applied locally
    if (_appliedJobs.containsKey(jobId)) {
      debugPrint('⚡ applyToJob: already applied (local cache) jobId=$jobId');
      return _appliedJobs[jobId];
    }

    // Deterministic application ID: app_{jobId}_{workerId}
    final appId = 'app_${jobId}_$workerId';
    debugPrint('📤 applyToJob: jobId=$jobId workerId=$workerId appId=$appId');

    try {
      // 1. Resolve hirerId and hirerName from canonical job doc if missing
      var resolvedHirerId = hirerId;
      var resolvedHirerName = hirerName;
      if (resolvedHirerId.isEmpty) {
        try {
          final jobDoc = await _db.collection('jobs').doc(jobId).get();
          if (jobDoc.exists) {
            final jd = jobDoc.data() ?? {};
            resolvedHirerId = (jd['hirerId'] ?? jd['hirerUid'] ?? jd['createdById'] ?? jd['createdBy'] ?? '').toString();
            if (resolvedHirerName.isEmpty) {
              resolvedHirerName = (jd['hirerName'] ?? jd['hirer'] ?? jd['createdByName'] ?? '').toString();
            }
          }
        } catch (jErr) {
          debugPrint('⚠️ applyToJob: could not resolve job hirer: $jErr');
        }
      }

      final appRef = _db.collection('applications').doc(appId);

      // 2. Check if already applied and inspect status
      List<dynamic> attemptHistory = [];
      try {
        final existing = await appRef.get();
        if (existing.exists) {
          final data = existing.data() ?? {};
          final currentStatus = (data['status'] as String? ?? 'pending').toLowerCase();

          // If already actively applied, return existing application without creating duplicate
          if (currentStatus == 'pending' || currentStatus == 'applied' || currentStatus == 'accepted' || currentStatus == 'shortlisted') {
            debugPrint('⚡ applyToJob: active application already exists ($currentStatus) for jobId=$jobId');
            _appliedJobs[jobId] = appId;
            notifyListeners();
            return appId;
          }

          // Re-application after withdrawal or rejection: preserve prior attempt history
          attemptHistory = List<dynamic>.from(data['attemptHistory'] ?? []);
          attemptHistory.add({
            'status': currentStatus,
            'appliedAt': data['appliedAt'],
            'withdrawnAt': data['updatedAt'] ?? data['withdrawnAt'],
            'message': data['message'] ?? '',
            'reappliedAt': Timestamp.now(),
          });
          debugPrint('🔄 applyToJob: re-applying after $currentStatus (prior attempts: ${attemptHistory.length})');
        }
      } catch (checkErr) {
        debugPrint('ℹ️ applyToJob: pre-check note: $checkErr');
      }

      // 3. Create or update application to pending
      await appRef.set({
        'jobId':           jobId,
        'workerId':        workerId,
        'workerName':      workerName,
        'workerPhoto':     workerPhoto,
        'workerRating':    workerRating,
        'workerTotalJobs': workerTotalJobs,
        'workerSkills':    workerSkills,
        'workerVerified':  workerVerified,
        'hirerId':         resolvedHirerId,
        'hirerName':       resolvedHirerName,
        'jobTitle':        jobTitle,
        'skill':           skill,
        'pay':             pay,
        'message':         message,
        'status':          'pending',
        'appliedAt':       FieldValue.serverTimestamp(),
        'updatedAt':       FieldValue.serverTimestamp(),
        if (attemptHistory.isNotEmpty) 'attemptHistory': attemptHistory,
      }, SetOptions(merge: true));

      _appliedJobs[jobId] = appId;
      notifyListeners();
      debugPrint('✅ applyToJob: SUCCESS appId=$appId');
      return appId;
    } on FirebaseException catch (fe) {
      debugPrint('❌ applyToJob FirebaseException: ${fe.code} ${fe.message}');
      _lastApplyError = fe.code == 'permission-denied'
          ? "You don't have permission to apply for this job. Please ensure your worker profile is approved."
          : (fe.message ?? 'Application submission failed. Please try again.');
      return null;
    } catch (e) {
      debugPrint('❌ applyToJob error: $e');
      _lastApplyError = 'Application submission failed. Please try again.';
      return null;
    }
  }

  /// Withdraw application (worker action)
  Future<bool> withdrawApplication(String applicationId, String jobId) async {
    try {
      await _db.collection('applications').doc(applicationId).update({
        'status': 'withdrawn',
        'withdrawnAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _appliedJobs.remove(jobId);
      notifyListeners();
      debugPrint('✅ withdrawApplication: $applicationId → withdrawn');
      return true;
    } catch (e) {
      debugPrint('❌ withdrawApplication error: $e');
      return false;
    }
  }

  /// Fetch private work location (authorized only for hirer owner, admin, or accepted worker)
  Future<WorkLocation?> fetchJobPrivateLocation(String jobId) async {
    try {
      final doc = await _db.collection('jobPrivate').doc(jobId).get();
      if (doc.exists && doc.data() != null) {
        return WorkLocation.fromMap(doc.data()!);
      }
    } catch (e) {
      debugPrint('🔒 fetchJobPrivateLocation: unauthorized or error: $e');
    }
    return null;
  }

  /// Real-time stream of worker's active applications
  void startAppliedJobsStream(String workerId) {
    if (workerId.isEmpty) return;
    _appliedJobsSub?.cancel();
    debugPrint('📥 startAppliedJobsStream: workerId=$workerId');
    _appliedJobsSub = _db
        .collection('applications')
        .where('workerId', isEqualTo: workerId)
        .snapshots()
        .listen(
      (snap) {
        final Map<String, String> active = {};
        for (final doc in snap.docs) {
          final data = doc.data();
          final status = (data['status'] as String? ?? 'pending').toLowerCase();
          final jId = data['jobId'] as String?;
          if (jId != null && status != 'withdrawn' && status != 'cancelled') {
            active[jId] = doc.id;
          }
        }
        _appliedJobs = active;
        debugPrint('✅ appliedJobs stream: ${_appliedJobs.length} active applications');
        notifyListeners();
      },
      onError: (e) {
        debugPrint('❌ appliedJobs stream error: $e');
      },
    );
  }

  /// Load existing applications for a worker (backward compatible helper)
  Future<void> loadAppliedJobs(String workerId) async {
    startAppliedJobsStream(workerId);
  }

  // ── Filter controls ───────────────────────────────────────────────────────
  void updateFilter(JobFilter f) { _filter = f; notifyListeners(); }
  void clearFilter()             { _filter = const JobFilter(); notifyListeners(); }
  void setSearch(String s)       { _filter = _filter.copyWith(search: s); notifyListeners(); }
  void setDistrict(String d)     { _filter = _filter.copyWith(district: d, taluk: ''); notifyListeners(); }
  void setTaluk(String t)        { _filter = _filter.copyWith(taluk: t); notifyListeners(); }
  void setSkill(String s)        { _filter = _filter.copyWith(skill: _filter.skill == s ? '' : s); notifyListeners(); }
  void setSort(SortMode s)       { _filter = _filter.copyWith(sort: s); notifyListeners(); }

  @override
  void dispose() {
    _authSub.cancel();
    _appliedJobsSub?.cancel();
    stopListening();
    stopHirerStream();
    super.dispose();
  }
}
