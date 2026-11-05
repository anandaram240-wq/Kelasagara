// lib/screens/jobs/work_detail_screen.dart
// Phase 5: Canonical Accepted Work Detail Screen for both Hirer and Worker.
// Displays Authorized Exact Job Location, Real-Time Status Timeline,
// Mutual Profile Access, Chat & Call CTAs, and Tracking Integration.

import 'package:flutter/material.dart' hide NavigationDestination;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/job_categories.dart';
import '../../providers/auth_provider.dart';
import '../../services/booking_service.dart';
import 'package:latlong2/latlong.dart';
import '../chat/chat_screen.dart';
import '../tracking/journey_navigator.dart';
import '../profile/worker_profile_detail_screen.dart';
import '../profile/hirer_profile_sheet.dart';
import '../../models/navigation_destination.dart';
import '../../services/navigation/navigation_location_provider.dart';
import '../../services/navigation/route_prefetch_manager.dart';
import '../../services/navigation/external_navigation_service.dart';
import '../tracking/work_completion_screen.dart';
import '../../features/tracking/presentation/widgets/worker_otp_verification_sheet.dart';
import '../../features/tracking/domain/arrival_eligibility_policy.dart';
import 'package:url_launcher/url_launcher.dart';

class WorkDetailScreen extends StatefulWidget {
  final String bookingId;

  const WorkDetailScreen({super.key, required this.bookingId});

  @override
  State<WorkDetailScreen> createState() => _WorkDetailScreenState();
}

class _WorkDetailScreenState extends State<WorkDetailScreen> with WidgetsBindingObserver {
  String? _prefetchedBookingId;
  LatLng? _currentWorkerPos;
  double _hirerRatingStars = 5.0;
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSubmittingReview = false;
  bool _isSubmittingCompletion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshWorkerLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWorkerLocation();
    }
  }

  Future<void> _refreshWorkerLocation() async {
    try {
      final fix = await NavigationLocationProvider.instance.getFreshLocation(
        timeout: const Duration(seconds: 3),
      );
      if (fix != null && mounted) {
        setState(() {
          _currentWorkerPos = LatLng(fix.latitude, fix.longitude);
        });
      }
    } catch (_) {}
  }

  void _maybePrefetchRoute({
    required String bookingId,
    required String jobId,
    required double lat,
    required double lng,
    required String address,
  }) {
    if (_prefetchedBookingId == bookingId) return;
    _prefetchedBookingId = bookingId;

    Future.microtask(() async {
      try {
        final dest = NavigationDestination(
          bookingId: bookingId,
          jobId: jobId,
          latitude: lat,
          longitude: lng,
          address: address,
          authorizedAt: DateTime.now(),
        );
        if (!dest.isValid) return;

        final fix = await NavigationLocationProvider.instance.getFreshLocation(
          timeout: const Duration(seconds: 4),
        );
        if (fix != null) {
          final origin = LatLng(fix.latitude, fix.longitude);
          await RoutePrefetchManager.instance.prefetchRoute(
            bookingId: bookingId,
            origin: origin,
            destination: dest,
            sessionId: 'prefetch_${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      } catch (e) {
        debugPrint('[WorkDetailScreen] Non-fatal prefetch error: $e');
      }
    });
  }

  Future<void> _makeCall(BuildContext context, String uid, String? phoneFallback) async {
    String? phone = phoneFallback;
    if (phone == null || phone.trim().isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        phone = doc.data()?['phone'] as String?;
      } catch (_) {}
    }
    if (phone == null || phone.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📞 Phone number not available for this user. Please use chat.'),
            backgroundColor: Color(0xFF1E293B),
          ),
        );
      }
      return;
    }
    final uri = Uri.parse('tel:${phone.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingId = widget.bookingId;
    final auth = context.watch<AuthProvider>();
    final myUid = auth.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textHead),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Confirmed Work Details',
          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHead),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMed),
            // B08 FIX: Refresh triggers StreamBuilder rebuild via setState
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {}); // StreamBuilder re-subscribes on rebuild
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('bookings').doc(bookingId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text('Error loading booking: ${snap.error}', style: GoogleFonts.plusJakartaSans(color: AppColors.red)),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final data = snap.data!.data() as Map<String, dynamic>;
          final isWorker = data['workerId'] == myUid;
          final status = data['status'] as String? ?? 'confirmed';

          // Safe Transition 4c reconciliation: if app crashed or disconnected before scrub, clean it up now
          if (isWorker && BookingStatus.isWorkingState(status) && data['otpAttempt'] != null) {
            FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
              'otpAttempt': FieldValue.delete(),
            }).catchError((_) {});
          }

          final jobTitle = data['jobTitle'] as String? ?? 'Work Assignment';
          final skillId = data['skillId'] as String? ?? '';
          final pay = (data['pay'] as num?)?.toInt() ?? 0;
          final counterpartName = isWorker
              ? (data['hirerName'] as String? ?? 'Hirer')
              : (data['workerName'] as String? ?? 'Worker');
          final counterpartId = isWorker
              ? (data['hirerId'] as String? ?? '')
              : (data['workerId'] as String? ?? '');

          final bookingDataMerged = <String, dynamic>{...data, 'bookingId': bookingId};
          final dest = BookingDestinationContract.fromBooking(bookingDataMerged);
          final lat = dest?.latitude ?? (data['jobLat'] as num?)?.toDouble() ?? (data['lat'] as num?)?.toDouble() ?? 0.0;
          final lng = dest?.longitude ?? (data['jobLng'] as num?)?.toDouble() ?? (data['lng'] as num?)?.toDouble() ?? 0.0;
          final address = (dest != null && dest.address.isNotEmpty)
              ? dest.address
              : (data['jobAddress'] as String? ?? data['address'] as String? ?? '');

          final cat = kJobCategories.firstWhere((c) => c.id == skillId, orElse: () => kJobCategories.first);

          if (isWorker &&
              (status == BookingStatus.confirmed || status == BookingStatus.tracking) &&
              lat != 0.0 &&
              lng != 0.0) {
            _maybePrefetchRoute(
              bookingId: bookingId,
              jobId: data['jobId'] as String? ?? '',
              lat: lat,
              lng: lng,
              address: address,
            );
          }

          double? computedDistanceToJob;
          if (lat != 0.0 && lng != 0.0) {
            if (_currentWorkerPos != null && _currentWorkerPos!.latitude != 0.0) {
              computedDistanceToJob = const Distance().as(LengthUnit.Meter, _currentWorkerPos!, LatLng(lat, lng));
            } else if (data['distanceToJob'] != null) {
              computedDistanceToJob = (data['distanceToJob'] as num).toDouble();
            }
          }
          final isArrivedAtSite = ArrivalEligibilityPolicy.canWorkerEnterOtp(
            status: status,
            trackingStatus: data['trackingStatus'] as String?,
            geofenceMilestone: data['geofenceMilestone'] as String?,
            distanceMeters: computedDistanceToJob,
            accuracyMeters: (data['workerAccuracy'] as num?)?.toDouble(),
            isSeed: false,
            arrivalVerified: data['arrivalVerified'] == true,
            arrivalOtpUsed: data['arrivalOtpUsed'] == true,
          );
          final isWithin75m = isArrivedAtSite;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Status Banner & Timeline ──
                _buildStatusTimeline(status),
                const SizedBox(height: 16),

                // ── Authorized Exact Location Card (UNLOCKED) ──
                _buildExactLocationCard(
                  context,
                  address: address,
                  lat: lat,
                  lng: lng,
                  jobTitle: jobTitle,
                  isWorker: isWorker,
                  status: status,
                  bookingData: {...data, 'bookingId': bookingId},
                  isWithin75m: isWithin75m,
                  isArrivedAtSite: isArrivedAtSite,
                ),
                const SizedBox(height: 16),

                // ── Work Scope & Agreed Terms ──
                _buildTermsCard(jobTitle, cat, pay, data['jobId'] as String? ?? ''),
                const SizedBox(height: 16),

                // ── Counterpart Profile Card ──
                _buildCounterpartCard(context, counterpartName, counterpartId, isWorker),
                const SizedBox(height: 20),

                // ── Primary Contextual CTA ──
                _buildWorkflowActions(
                  context,
                  isWorker,
                  status,
                  data,
                  counterpartName,
                  counterpartId,
                  jobTitle,
                  isWithin75m,
                  isArrivedAtSite,
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    final steps = [
      {'status': BookingStatus.confirmed, 'label': 'Confirmed'},
      {'status': BookingStatus.tracking, 'label': 'En Route'},
      {'status': BookingStatus.arrived, 'label': 'Arrived'},
      {'status': BookingStatus.working, 'label': 'Working'},
      {'status': BookingStatus.completionVerified, 'label': 'Completed'},
    ];

    int currentIndex = steps.indexWhere((s) => s['status'] == status);
    if (currentIndex == -1) {
      if (BookingStatus.isWorkingState(status) || status == BookingStatus.completionRequested) {
        currentIndex = 3;
      } else if (status == BookingStatus.completionVerified || status == BookingStatus.completed) {
        currentIndex = 4;
      } else {
        currentIndex = 0;
      }
    }

    return Container(
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.greenPale,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'STATUS: ${status.replaceAll("_", " ").toUpperCase()}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.green,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Booking ID: ${widget.bookingId.length > 12 ? widget.bookingId.substring(0, 12) : widget.bookingId}',
                style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(steps.length * 2 - 1, (i) {
              if (i.isOdd) {
                final lineIndex = i ~/ 2;
                final isDone = lineIndex < currentIndex;
                return Expanded(
                  child: Container(
                    height: 3,
                    color: isDone ? AppColors.green : AppColors.divider,
                  ),
                );
              }
              final stepIndex = i ~/ 2;
              final isDone = stepIndex <= currentIndex;
              return Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? AppColors.green : AppColors.surface2,
                  border: Border.all(
                    color: isDone ? AppColors.green : AppColors.border,
                    width: 2,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: steps.map((s) => Text(
              s['label'] as String,
              style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textFaint),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExactLocationCard(
    BuildContext context, {
    required String address,
    required double lat,
    required double lng,
    required String jobTitle,
    required bool isWorker,
    required String status,
    required Map<String, dynamic> bookingData,
    bool isWithin75m = false,
    bool isArrivedAtSite = false,
  }) {
    final canWorkerNavigate = isWorker && (status == 'confirmed' || status == 'tracking');
    final isHirerActive = !isWorker && (status == 'confirmed' || status == 'tracking');
    final otpAlreadyVerified = bookingData['arrivalVerified'] == true ||
        bookingData['arrivalOtpUsed'] == true ||
        BookingStatus.isWorkingState(status) ||
        status == BookingStatus.completionRequested ||
        status == BookingStatus.completionVerified ||
        status == BookingStatus.completed ||
        status == BookingStatus.disputed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.green, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_open, color: AppColors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                'Authorized Work Site Location',
                style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.green),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            address.isNotEmpty ? address : 'Address provided upon acceptance',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead, height: 1.4, fontWeight: FontWeight.w600),
          ),
          if (lat != 0.0 && lng != 0.0) ...[
            const SizedBox(height: 6),
            Text(
              '${lat.toStringAsFixed(5)}°N, ${lng.toStringAsFixed(5)}°E',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textFaint),
            ),
            const SizedBox(height: 12),
            // ── WORKER ACTION BUTTONS ──
            if (canWorkerNavigate) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final auth = context.read<AuthProvider>();
                    ExternalNavigationService.instance.openGoogleMapsForBooking(
                      context,
                      currentWorkerId: auth.uid ?? '',
                      bookingData: bookingData,
                      expectedJobId: bookingData['jobId'] as String?,
                    );
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: Text(
                    'Open in Google Maps 🗺',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (isWorker && !otpAlreadyVerified && (isArrivedAtSite || status == BookingStatus.arrived)) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final counterpartName = bookingData['hirerName'] as String? ?? 'Hirer';
                      final bId = (bookingData['bookingId'] as String?) ?? widget.bookingId;
                      final auth = context.read<AuthProvider>();
                      if (status != 'arrived') {
                        await BookingService.instance.recordArrival(
                          workerUid: auth.uid ?? '',
                          bookingId: bId,
                        );
                      }
                      if (!context.mounted) return;
                      WorkerOtpVerificationSheet.show(
                        context,
                        bookingId: bId,
                        hirerName: counterpartName,
                        jobTitle: jobTitle,
                        onVerified: () {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Arrival Verified! Work Started 🔨'),
                                backgroundColor: AppColors.green,
                              ),
                            );
                          }
                        },
                      );
                    },
                    icon: const Icon(Icons.key_rounded, size: 16),
                    label: Text(
                      'Enter Customer OTP 🔑 • Verify & Start Job',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ] else if (status == 'tracking') ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gps_fixed_rounded, size: 16, color: Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'En Route: Live tracking active. Arrival OTP unlocks automatically when you arrive within 75m.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF166534),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ] else if (isWorker) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final auth = context.read<AuthProvider>();
                    ExternalNavigationService.instance.openGoogleMapsForBooking(
                      context,
                      currentWorkerId: auth.uid ?? '',
                      bookingData: bookingData,
                      expectedJobId: bookingData['jobId'] as String?,
                    );
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: Text(
                    'Open in Google Maps 🗺',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]
            // ── HIRER ACTION BUTTONS ──
            else if (isHirerActive) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    JourneyNavigator.openHirer(
                      context,
                      booking: bookingData,
                    );
                  },
                  icon: const Icon(Icons.location_searching, size: 18),
                  label: Text(
                    'Track Worker Live on Map 🛰️',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else if (!isWorker && status == 'arrived') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    JourneyNavigator.openHirer(
                      context,
                      booking: bookingData,
                    );
                  },
                  icon: const Icon(Icons.pin_drop_rounded, size: 18),
                  label: Text(
                    'Worker Arrived — Verify OTP 📍',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else if (!isWorker && (status == 'working' || status == 'completion_requested')) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final auth = context.read<AuthProvider>();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkCompletionScreen(
                          bookingId: widget.bookingId,
                          workerId: (bookingData['workerId'] as String?) ?? '',
                          hirerId: auth.uid ?? '',
                          jobId: (bookingData['jobId'] as String?) ?? '',
                          skillId: (bookingData['skillId'] as String?) ?? 'general',
                          workerName: (bookingData['workerName'] as String?) ?? '',
                          jobTitle: jobTitle,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.star_rounded, size: 20),
                  label: Text(
                    '⭐ Work Done? Confirm & Rate',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTermsCard(String jobTitle, JobCategory cat, int pay, String jobId) {
    return Container(
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
                      jobTitle,
                      style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textHead),
                    ),
                    Text(
                      cat.label,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹$pay',
                    style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                  ),
                  Text(
                    'per day',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCounterpartCard(BuildContext context, String name, String uid, bool isWorker) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isWorker ? 'Hirer Information' : 'Worker Information',
            style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primaryPale,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.verified, size: 12, color: AppColors.green),
                        const SizedBox(width: 4),
                        Text(
                          'Verified Party',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isWorker)
                OutlinedButton(
                  onPressed: () {
                    WorkerProfileDetailScreen.open(context, uid);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: Text('View Profile', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
                )
              else
                OutlinedButton(
                  onPressed: () {
                    HirerPublicProfileSheet.show(context, hirerId: uid, fallbackName: name);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: Text('Hirer Profile', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          workerName: name,
                          jobTitle: 'Booking Discussion',
                          otherUserId: uid,
                          jobId: widget.bookingId,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: Text('Chat', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _makeCall(context, uid, null),
                  icon: const Icon(Icons.phone_rounded, size: 16, color: Color(0xFF16A34A)),
                  label: Text('Call', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowActions(
    BuildContext context,
    bool isWorker,
    String status,
    Map<String, dynamic> bookingData,
    String counterpartName,
    String counterpartId,
    String jobTitle,
    bool isWithin75m,
    bool isArrivedAtSite,
  ) {
    // 1. DISPUTED
    if (status == BookingStatus.disputed) {
      return _buildDisputedCard(context, bookingData, isWorker);
    }

    // 2. COMPLETED & 3. COMPLETION VERIFIED
    if (status == BookingStatus.completionVerified || status == BookingStatus.completed) {
      return _buildMutualCompletionCard(
        context,
        isWorker,
        bookingData,
        counterpartName,
        counterpartId,
      );
    }

    // 4. COMPLETION REQUESTED & 5. WORKING / IN PROGRESS
    if (BookingStatus.isWorkingState(status) || status == BookingStatus.completionRequested) {
      return isWorker
          ? _buildWorkerDualCompletionCard(context, bookingData, counterpartName)
          : _buildHirerDualCompletionCard(context, bookingData, counterpartName);
    }

    // 6. ARRIVED (with OTP unverified)
    final otpAlreadyVerified = bookingData['arrivalVerified'] == true ||
        bookingData['arrivalOtpUsed'] == true;

    if (!otpAlreadyVerified && (status == BookingStatus.arrived || isArrivedAtSite)) {
      return isWorker
          ? _buildWorkerArrivedCard(context, counterpartName, jobTitle, bookingData)
          : _buildHirerArrivedCard(context, counterpartName, bookingData);
    }

    if (isWorker) {
      // 7. Tracking (not yet arrived)
      if (status == BookingStatus.tracking) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.explore_rounded, color: Color(0xFF16A34A), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'En Route to Work Site 🧭 • ಲೈವ್ ಜಿಪಿಎಸ್ ಸಕ್ರಿಯವಾಗಿದೆ',
                          style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF14532D)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Live location is shared with $counterpartName. In-app navigation detects when you reach within 75m to unlock Arrival OTP entry.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF166534)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final auth = context.read<AuthProvider>();
                    ExternalNavigationService.instance.openGoogleMapsForBooking(
                      context,
                      currentWorkerId: auth.uid ?? '',
                      bookingData: {...bookingData, 'bookingId': widget.bookingId},
                      expectedJobId: bookingData['jobId'] as String?,
                    );
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: Text(
                    'Open in Google Maps 🗺️',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      // 4. Confirmed
      if (status == BookingStatus.confirmed) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF6EE7B7), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD1FAE5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.celebration_rounded, color: Color(0xFF059669), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You are Hired for this Job! 🎉',
                          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF065F46)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hirer $counterpartName is expecting you. Start your journey now.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF047857), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final auth = context.read<AuthProvider>();
                    ExternalNavigationService.instance.openGoogleMapsForBooking(
                      context,
                      currentWorkerId: auth.uid ?? '',
                      bookingData: {...bookingData, 'bookingId': widget.bookingId},
                      expectedJobId: bookingData['jobId'] as String?,
                    );
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: Text(
                    'Open in Google Maps 🗺️',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } else {
      // ── Hirer Actions: Confirmed or Tracking ──
      if (status == BookingStatus.confirmed || status == BookingStatus.tracking) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_searching, color: Color(0xFF16A34A), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status == BookingStatus.tracking ? 'Worker En Route 🛰️' : 'Worker Confirmed! 🎉',
                          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF14532D)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$counterpartName is on the way. You can track live movement on the map.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF166534), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    JourneyNavigator.openHirer(
                      context,
                      booking: {...bookingData, 'bookingId': widget.bookingId},
                    );
                  },
                  icon: const Icon(Icons.location_searching, size: 18),
                  label: Text(
                    'Track Worker Live on Map 🛰️',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    return const SizedBox.shrink();
  }

  Widget _buildWorkerArrivedCard(
    BuildContext context,
    String counterpartName,
    String jobTitle,
    Map<String, dynamic> bookingData,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pin_drop_rounded, color: Color(0xFFD97706), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doorstep Arrival (Within 75m) 📍',
                      style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF78350F)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'You have reached the customer location. Ask $counterpartName for the 6-digit Arrival OTP to start work.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF92400E)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final auth = context.read<AuthProvider>();
                final bId = (bookingData['bookingId'] as String?) ?? widget.bookingId;
                if (bookingData['status'] != 'arrived') {
                  await BookingService.instance.recordArrival(
                    workerUid: auth.uid ?? '',
                    bookingId: bId,
                  );
                }
                if (!context.mounted) return;
                WorkerOtpVerificationSheet.show(
                  context,
                  bookingId: bId,
                  hirerName: counterpartName,
                  jobTitle: jobTitle,
                  onVerified: () {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Arrival Verified! Work Started 🔨'),
                          backgroundColor: AppColors.green,
                        ),
                      );
                    }
                  },
                );
              },
              icon: const Icon(Icons.key_rounded, size: 18),
              label: Text(
                'Enter Customer OTP 🔑 • Verify & Start Job',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerDualCompletionCard(
    BuildContext context,
    Map<String, dynamic> data,
    String counterpartName,
  ) {
    final workerStatus = data['workerCompletionStatus'] as String? ??
        (data['status'] == BookingStatus.completionRequested ? 'completed' : 'pending');
    final hirerStatus = data['hirerCompletionStatus'] as String? ?? 'pending';

    final isWorkerDone = workerStatus == 'completed';
    final isHirerDone = hirerStatus == 'completed';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.primaryPale,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.handshake_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dual-Party Completion Status',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Both parties must independently confirm completion before job is verified.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMed),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Worker (You):', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isWorkerDone ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isWorkerDone ? 'Confirmed Completed ✓' : 'Pending Your Action ⏳',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isWorkerDone ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Hirer ($counterpartName):', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isHirerDone ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isHirerDone ? 'Confirmed Completed ✓' : 'Awaiting Confirmation ⏳',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isHirerDone ? const Color(0xFF16A34A) : AppColors.textFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!isWorkerDone) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmittingCompletion ? null : () => _confirmWorkerCompletion(true),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('Mark Work Completed ✓', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSubmittingCompletion ? null : () => _confirmWorkerCompletion(false),
                icon: const Icon(Icons.report_problem_outlined, size: 16, color: AppColors.red),
                label: Text('Mark Not Completed / Report Issue ⚠️', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFF059669)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You confirmed completion. Waiting for $counterpartName to inspect and confirm.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF065F46)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHirerArrivedCard(
    BuildContext context,
    String counterpartName,
    Map<String, dynamic> bookingData,
  ) {
    final bId = (bookingData['bookingId'] as String?) ?? widget.bookingId;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .doc(bId)
          .collection('hirer_secure')
          .doc('arrival_code')
          .snapshots(),
      builder: (context, snapshot) {
        final secureOtp = snapshot.data?.data()?['arrivalOtp']?.toString().trim();
        final arrivalOtp = (secureOtp != null && secureOtp.isNotEmpty)
            ? secureOtp
            : '******';

        final isLocked = bookingData['arrivalOtpLocked'] == true ||
            ((bookingData['arrivalOtpAttempts'] as num?)?.toInt() ?? 0) >= 5;
        final rawExpiry = bookingData['arrivalOtpExpiry'];
        DateTime? expiry;
        if (rawExpiry is Timestamp) expiry = rawExpiry.toDate();
        final isExpired = expiry != null && DateTime.now().isAfter(expiry);
        final isMissingExpiry = rawExpiry == null;

        if (isLocked || isExpired || isMissingExpiry) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_clock_rounded, color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isLocked ? 'OTP ಲಾಕ್ ಆಗಿದೆ (OTP Locked)' : 'OTP ಅವಧಿ ಮೀರಿದೆ (OTP Expired)',
                            style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF991B1B)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isLocked
                                ? '5 ವಿಫಲ ಪ್ರಯತ್ನಗಳ ಕಾರಣ ಈ ಕೋಡ್ ಲಾಕ್ ಆಗಿದೆ. ಕೆಲಸ ಮುಂದುವರಿಸಲು ಹೊಸ OTP ರಚಿಸಿ.'
                                : 'ಈ ಆಗಮನದ ಕೋಡ್ ಅವಧಿ ಮೀರಿದೆ. ಹೊಸ ಕೋಡ್ ರಚಿಸಿ.',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFFB91C1C)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final res = await BookingService.instance.regenerateArrivalOtp(bookingId: bId);
                      if (res.success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('ಹೊಸ OTP ಯಶಸ್ವಿಯಾಗಿ ರಚಿಸಲಾಗಿದೆ: ${res.newOtp}'),
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      } else if (!res.success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('ದೋಷ: ${res.error}'),
                            backgroundColor: const Color(0xFFDC2626),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: Text(
                      'ಹೊಸ OTP ರಚಿಸಿ • Regenerate OTP',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF93C5FD), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDBEAFE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pin_drop_rounded, color: Color(0xFF2563EB), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Worker Arrived at Site 📍',
                          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1E3A8A)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$counterpartName has arrived. Share your 6-digit Arrival OTP to authorize and start work.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF1E40AF)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Column(
                  children: [
                    Text('YOUR ARRIVAL OTP',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: const Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    Text(
                      arrivalOtp,
                      style: GoogleFonts.sora(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8, color: const Color(0xFF1D4ED8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: arrivalOtp));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('OTP copied to clipboard 📋'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF2563EB)),
                  label: Text(
                    'Copy Code',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF2563EB)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF93C5FD)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    JourneyNavigator.openHirer(
                      context,
                      booking: {...bookingData, 'bookingId': widget.bookingId},
                    );
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: Text(
                    'Open Tracking Map 🛰️',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHirerDualCompletionCard(
    BuildContext context,
    Map<String, dynamic> data,
    String counterpartName,
  ) {
    final workerStatus = data['workerCompletionStatus'] as String? ??
        (data['status'] == BookingStatus.completionRequested ? 'completed' : 'pending');
    final hirerStatus = data['hirerCompletionStatus'] as String? ?? 'pending';

    final isWorkerDone = workerStatus == 'completed';
    final isHirerDone = hirerStatus == 'completed';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.primaryPale,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fact_check_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Work Completion Verification',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Inspect the work. Both parties must confirm completion before rating is unlocked.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMed),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Worker ($counterpartName):', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isWorkerDone ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isWorkerDone ? 'Marked Completed ✓' : 'Working in Progress 🔨',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isWorkerDone ? const Color(0xFF16A34A) : AppColors.textFaint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Hirer (You):', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isHirerDone ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isHirerDone ? 'Confirmed Completed ✓' : 'Pending Inspection ⏳',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isHirerDone ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!isHirerDone) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmittingCompletion ? null : () => _confirmHirerCompletion(true),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('Confirm Work Completed ✓', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSubmittingCompletion ? null : () => _confirmHirerCompletion(false),
                icon: const Icon(Icons.report_problem_outlined, size: 16, color: AppColors.red),
                label: Text('Mark Not Completed / Report Dispute ⚠️', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFF059669)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You confirmed completion. Once $counterpartName confirms, mutual completion & ratings will unlock.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF065F46)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMutualCompletionCard(
    BuildContext context,
    bool isWorker,
    Map<String, dynamic> data,
    String counterpartName,
    String counterpartId,
  ) {
    final hirerRated = data['hirerRated'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.green.withAlpha(120), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.greenPale,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_rounded, color: AppColors.green, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Work Verified & Mutually Completed 🎉',
                        style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green)),
                    const SizedBox(height: 2),
                    Text('Both parties confirmed. Recorded in Verified Work Ledger.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMed)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),

          // ── HIRER RATING & WRITTEN FEEDBACK WORKFLOW ──
          if (!isWorker) ...[
            if (hirerRated) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 18),
                        const SizedBox(width: 8),
                        Text('Your Rating & Feedback Submitted',
                            style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(5, (i) {
                        final star = (i + 1).toDouble();
                        final givenStars = (data['hirerRatingStars'] as num?)?.toDouble() ?? 5.0;
                        return Icon(
                          star <= givenStars ? Icons.star_rounded : Icons.star_border_rounded,
                          color: const Color(0xFFF59E0B),
                          size: 20,
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '"${data['hirerRatingFeedback'] ?? ''}"',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textHead),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rate & Review $counterpartName ⭐',
                      style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF14532D)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Work is mutually verified! Please rate the worker and provide written feedback.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF166534)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (index) {
                            final starVal = (index + 1).toDouble();
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _hirerRatingStars = starVal);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  starVal <= _hirerRatingStars ? Icons.star_rounded : Icons.star_border_rounded,
                                  color: starVal <= _hirerRatingStars ? const Color(0xFFF59E0B) : AppColors.border,
                                  size: 32,
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_hirerRatingStars.toStringAsFixed(1)} / 5.0',
                          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF14532D)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _feedbackController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Write feedback about quality, punctuality and service...',
                        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textFaint),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF86EFAC)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF86EFAC)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmittingReview ? null : () => _submitHirerRatingAndFeedback(counterpartId),
                        icon: _isSubmittingReview
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.star_rate_rounded, size: 18),
                        label: Text(
                          _isSubmittingReview ? 'Submitting...' : 'Submit Rating & Feedback 🌟',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            if (hirerRated) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hirer Rating & Feedback',
                        style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                    const SizedBox(height: 6),
                    Row(
                      children: List.generate(5, (i) {
                        final star = (i + 1).toDouble();
                        final givenStars = (data['hirerRatingStars'] as num?)?.toDouble() ?? 5.0;
                        return Icon(
                          star <= givenStars ? Icons.star_rounded : Icons.star_border_rounded,
                          color: const Color(0xFFF59E0B),
                          size: 20,
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '"${data['hirerRatingFeedback'] ?? ''}"',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textHead),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.textFaint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Awaiting Hirer rating and feedback.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMed),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDisputedCard(BuildContext context, Map<String, dynamic> data, bool isWorker) {
    final reason = (data['hirerCompletionNotes'] as String?)?.isNotEmpty == true
        ? data['hirerCompletionNotes']
        : ((data['workerCompletionNotes'] as String?)?.isNotEmpty == true
            ? data['workerCompletionNotes']
            : (data['disputeReason'] as String? ?? 'Completion disputed by party'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.gavel_rounded, color: AppColors.red, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Completion Disputed ⚠️',
                        style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF991B1B))),
                    const SizedBox(height: 2),
                    Text('Work completion was marked incomplete. Mediation active.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFFB91C1C))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Text(
              'Reported Note: $reason',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF7F1D1D)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmWorkerCompletion(bool completed) async {
    final auth = context.read<AuthProvider>();
    final workerUid = auth.uid ?? '';
    if (workerUid.isEmpty) return;

    String? notes;
    if (completed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Mark Work Completed?', style: GoogleFonts.sora(fontWeight: FontWeight.w800)),
          content: Text(
            'Both you and the Hirer must independently confirm completion for the job to be officially verified.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textMed),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
              child: const Text('Confirm Completed'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else {
      final reasonCtrl = TextEditingController();
      final reported = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Report Issue / Incomplete', style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: AppColors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Please specify why work cannot be completed. This will pause completion and mark the booking disputed.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textMed),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Reason for non-completion...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
              child: const Text('Mark Not Completed'),
            ),
          ],
        ),
      );
      if (reported != true) return;
      notes = reasonCtrl.text.trim();
    }

    setState(() => _isSubmittingCompletion = true);
    final res = await BookingService.instance.recordWorkerCompletion(
      workerUid: workerUid,
      bookingId: widget.bookingId,
      completed: completed,
      notes: notes,
    );
    if (!mounted) return;
    setState(() => _isSubmittingCompletion = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.success
            ? (completed ? '✅ Work marked completed! Awaiting Hirer confirmation.' : '⚠️ Work marked not completed.')
            : 'Error: ${res.errorMessage ?? "Failed"}'),
        backgroundColor: res.success ? (completed ? AppColors.green : AppColors.red) : AppColors.red,
      ),
    );
  }

  Future<void> _confirmHirerCompletion(bool completed) async {
    final auth = context.read<AuthProvider>();
    final hirerUid = auth.uid ?? '';
    if (hirerUid.isEmpty) return;

    String? notes;
    if (completed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Confirm Work Completed?', style: GoogleFonts.sora(fontWeight: FontWeight.w800)),
          content: Text(
            'Confirm that the worker has completed the agreed scope of work satisfactorily.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textMed),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
              child: const Text('Confirm Completed'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else {
      final reasonCtrl = TextEditingController();
      final reported = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Report Issue / Dispute', style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: AppColors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Please specify the reason. This will pause completion and mark the booking disputed.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textMed),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Reason for non-completion...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
              child: const Text('Mark Not Completed'),
            ),
          ],
        ),
      );
      if (reported != true) return;
      notes = reasonCtrl.text.trim();
    }

    setState(() => _isSubmittingCompletion = true);
    final res = await BookingService.instance.recordHirerCompletion(
      hirerUid: hirerUid,
      bookingId: widget.bookingId,
      completed: completed,
      notes: notes,
    );
    if (!mounted) return;
    setState(() => _isSubmittingCompletion = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.success
            ? (completed ? '✅ Work confirmed completed!' : '⚠️ Work marked not completed / disputed.')
            : 'Error: ${res.errorMessage ?? "Failed"}'),
        backgroundColor: res.success ? (completed ? AppColors.green : AppColors.red) : AppColors.red,
      ),
    );
  }

  Future<void> _submitHirerRatingAndFeedback(String workerUid) async {
    final auth = context.read<AuthProvider>();
    final hirerUid = auth.uid ?? '';
    if (hirerUid.isEmpty) return;

    final feedback = _feedbackController.text.trim();
    if (feedback.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please write feedback before submitting.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmittingReview = true);
    final res = await BookingService.instance.submitHirerReview(
      bookingId: widget.bookingId,
      hirerUid: hirerUid,
      workerUid: workerUid,
      stars: _hirerRatingStars,
      feedback: feedback,
    );

    if (!mounted) return;
    setState(() => _isSubmittingReview = false);
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Rating & feedback submitted successfully!'),
          backgroundColor: AppColors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${res.errorMessage ?? "Failed"}'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }
}
