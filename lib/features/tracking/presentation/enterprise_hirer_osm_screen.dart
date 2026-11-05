import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../domain/geofence_dwell_engine.dart';
import '../domain/hmm_viterbi_shadow_matcher.dart';
import '../domain/trail_jitter_buffer_scheduler.dart';
import '../repositories/valhalla_osm_shadow_repository.dart';
import '../../../services/booking_service.dart';

class EnterpriseHirerOsmScreen extends StatefulWidget {
  final String bookingId;
  final String workerId;
  final String workerName;
  final String workerPhone;
  final LatLng jobDestination;

  const EnterpriseHirerOsmScreen({
    super.key,
    required this.bookingId,
    required this.workerId,
    required this.workerName,
    required this.workerPhone,
    required this.jobDestination,
  });

  @override
  State<EnterpriseHirerOsmScreen> createState() =>
      _EnterpriseHirerOsmScreenState();
}

class _EnterpriseHirerOsmScreenState extends State<EnterpriseHirerOsmScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final HmmViterbiShadowMatcher _viterbiMatcher = HmmViterbiShadowMatcher();
  final TrailJitterBufferScheduler _jitterScheduler =
      TrailJitterBufferScheduler();
  final ValhallaOsmShadowRepository _valhallaRepo =
      ValhallaOsmShadowRepository.instance;
  late final GeofenceDwellEngine _geofenceEngine;

  late final Ticker _ticker;

  // 60fps Display State
  LatLng? _displayPos;
  double _displayBearing = 0.0;
  bool _isDeadReckoning = false;
  ShadowTrackingMode _shadowMode = ShadowTrackingMode.osmRoadLocked;

  // Polylines
  List<LatLng> _masterOsmRoute = [];
  List<LatLng> _activeOsmRoute = [];
  List<LatLng> _cubicBezierBridge = [];

  // Telemetry & Security State
  String _workerConnState = 'online';
  bool _isMockLocationFlagged = false;
  bool _cameraAutoFollow = true;
  double _remainingDistanceM = 0.0;
  int _etaMinutes = 0;
  double _emaSpeedMps = 6.94;
  String _arrivalOtp = '------';
  String _bookingStatus = 'assigned';
  bool _isOtpLocked = false;
  int _lastSeq = -1;
  int _lastPacketWallMs = 0;
  int _secondsSinceLastPing = 0;
  bool _isFetchingRoute = false;
  BilingualNotificationPayload? _geofenceBanner;

  StreamSubscription<DatabaseEvent>? _rtdbSub;
  StreamSubscription<DocumentSnapshot>? _firestoreSub;
  StreamSubscription<DocumentSnapshot>? _otpSub;
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    _geofenceEngine = GeofenceDwellEngine(destination: widget.jobDestination);
    _ticker = createTicker(_on60FpsTick)..start();
    _initializeEnterprisePipeline();
  }

  void _on60FpsTick(Duration elapsed) {
    if (!_jitterScheduler.isInitialized || !mounted) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final SchedulerRenderFrame frame = _jitterScheduler.tickFrame(nowMs);

    if (_displayPos == null ||
        frame.position.latitude != _displayPos!.latitude ||
        frame.position.longitude != _displayPos!.longitude ||
        (frame.bearingDeg - _displayBearing).abs() > 0.2) {
      setState(() {
        _displayPos = frame.position;
        _displayBearing = frame.bearingDeg;
        _isDeadReckoning = frame.isDeadReckoning;
      });
    }
  }

  Future<void> _initializeEnterprisePipeline() async {
    await _seedZeroBlankStateFromFirestore();

    _firestoreSub = FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data != null && mounted) {
        final dynamic rawExp = data['arrivalOtpExpiry'];
        DateTime? exp;
        if (rawExp is Timestamp) exp = rawExp.toDate();
        final bool isExpired = exp != null && DateTime.now().isAfter(exp);
        final bool isMissingExpiry = rawExp == null;

        setState(() {
          _bookingStatus = (data['status'] ?? _bookingStatus).toString();
          _isOtpLocked = data['arrivalOtpLocked'] == true ||
              ((data['arrivalOtpAttempts'] as num?)?.toInt() ?? 0) >= 5 ||
              isExpired ||
              isMissingExpiry;
        });
      }
    });

    _otpSub = FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .collection('hirer_secure')
        .doc('arrival_code')
        .snapshots()
        .listen((secSnap) {
      final sOtp = secSnap.data()?['arrivalOtp']?.toString().trim();
      if (sOtp != null && sOtp.isNotEmpty && mounted) {
        setState(() => _arrivalOtp = sOtp);
      }
    });

    _rtdbSub = FirebaseDatabase.instance
        .ref('liveTracking/${widget.bookingId}')
        .onValue
        .listen(_onRtdbTelemetryPacket);

    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastPacketWallMs == 0 || !mounted) return;
      final int sec =
          ((DateTime.now().millisecondsSinceEpoch - _lastPacketWallMs) / 1000)
              .round()
              .clamp(0, 9999);
      setState(() => _secondsSinceLastPing = sec);
    });
  }

  Future<void> _seedZeroBlankStateFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();
      final data = doc.data();
      if (data == null) return;

      try {
        final secSnap = await FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .collection('hirer_secure')
            .doc('arrival_code')
            .get();
        final sOtp = secSnap.data()?['arrivalOtp']?.toString().trim();
        if (sOtp != null && sOtp.isNotEmpty) {
          _arrivalOtp = sOtp;
        }
      } catch (_) {}
      _bookingStatus = (data['status'] ?? 'assigned').toString();

      final seed = data['workerSeedLocation'] as Map<String, dynamic>?;
      if (seed != null && seed['lat'] != null && seed['lng'] != null) {
        final LatLng seedPt = LatLng(
          (seed['lat'] as num).toDouble(),
          (seed['lng'] as num).toDouble(),
        );
        await _fetchHeadingBiasedRoute(seedPt, 0.0);
        _processPacketAndSchedule(
          pos: seedPt,
          heading: 0.0,
          speedMps: 0.0,
          accuracyM: 12.0,
          trail: const [],
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {}
  }

  Future<void> _onRtdbTelemetryPacket(DatabaseEvent event) async {
    final map = event.snapshot.value as Map<dynamic, dynamic>?;
    if (map == null) return;

    final int seq = (map['seq'] as num?)?.toInt() ?? 0;
    if (seq < _lastSeq) return;
    _lastSeq = seq;

    final double lat = (map['lat'] as num?)?.toDouble() ?? 0.0;
    final double lng = (map['lng'] as num?)?.toDouble() ?? 0.0;
    if (lat == 0.0 && lng == 0.0) return;

    _lastPacketWallMs = DateTime.now().millisecondsSinceEpoch;
    _secondsSinceLastPing = 0;

    final double heading =
        (map['heading'] as num?)?.toDouble() ?? _displayBearing;
    final double speedMps = (map['speedMps'] as num?)?.toDouble() ?? 0.0;
    final double accuracyM = (map['accuracy'] as num?)?.toDouble() ?? 10.0;
    final String connState = (map['connectionState'] ?? 'online').toString();
    final bool isMocked = (map['isMockLocationFlagged'] as bool?) ?? false;
    final bool isSeed = (map['isSeed'] as bool?) ?? false;

    final List<Map<String, dynamic>> parsedTrail = [];
    if (map['trail'] is List) {
      for (final item in (map['trail'] as List)) {
        if (item is Map) {
          parsedTrail.add(Map<String, dynamic>.from(item));
        }
      }
    }

    if (mounted) {
      setState(() {
        _workerConnState = connState;
        _isMockLocationFlagged = isMocked;
      });
    }

    await _processPacketAndSchedule(
      pos: LatLng(lat, lng),
      heading: heading,
      speedMps: speedMps,
      accuracyM: accuracyM,
      trail: parsedTrail,
      timestampMs: _lastPacketWallMs,
      isSeed: isSeed,
    );
  }

  Future<void> _processPacketAndSchedule({
    required LatLng pos,
    required double heading,
    required double speedMps,
    required double accuracyM,
    required List<Map<String, dynamic>> trail,
    required int timestampMs,
    bool isSeed = false,
  }) async {
    if (_masterOsmRoute.isEmpty && !_isFetchingRoute) {
      await _fetchHeadingBiasedRoute(pos, heading);
    }

    // 1. Run Sliding-Window Viterbi HMM Map Matcher
    final ViterbiMatchOutput match = _viterbiMatcher.match(
      workerPos: pos,
      workerHeadingDeg: heading,
      workerSpeedMps: speedMps,
      osmPolyline: _masterOsmRoute,
    );

    // 2. Enqueue all unseen sub-vertices from `trail` into the 60fps Jitter Buffer
    _jitterScheduler.enqueueTrailBatch(
      rawTrail: trail,
      fallbackMatchedPos: match.matchedPosition,
      fallbackBearingDeg: match.matchedBearingDeg,
      fallbackSpeedMps: speedMps,
      packetTimestampMs: timestampMs,
      roadProjector: (pt, hdg, spd) {
        if (match.mode == ShadowTrackingMode.googleShortcutGlide) return pt;
        return _viterbiMatcher
            .match(
              workerPos: pt,
              workerHeadingDeg: hdg,
              workerSpeedMps: spd,
              osmPolyline: _masterOsmRoute,
            )
            .matchedPosition;
      },
    );

    // 3. Trigger Heading-Biased Valhalla Reroute if on persistent Gully Shortcut
    if (match.requiresHeadingBiasedReroute && !_isFetchingRoute) {
      unawaited(_fetchHeadingBiasedRoute(pos, match.matchedBearingDeg));
    }

    // 4. Dynamic Road ETA with EMA velocity + Bengaluru intersection penalty
    if (speedMps > 1.0) {
      _emaSpeedMps = (_emaSpeedMps * 0.72) + (speedMps.clamp(2.5, 16.5) * 0.28);
    }
    final int etaMins =
        ((match.remainingRouteMeters / (_emaSpeedMps * 0.82)) / 60.0)
            .ceil()
            .clamp(1, 180);

    // 5. Flyover-Safe Geofence Dwell Check on RAW GPS coordinate (presentation interpolation never affects arrival)
    if (!_isMockLocationFlagged) {
      final GeofenceEvaluationResult eval = _geofenceEngine.evaluateFix(
        workerPosition: pos,
        speedMps: speedMps,
        accuracyMeters: accuracyM,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
        isSeed: isSeed,
      );
      if (eval.hasTransition && eval.currentStage != GeofenceStage.enRoute) {
        _geofenceBanner = GeofenceDwellEngine.buildBilingualAlert(
          milestone: eval.currentStage,
          workerName: widget.workerName,
          arrivalOtp: _arrivalOtp,
        );
        unawaited(
          GeofenceDwellEngine.persistGeofenceTransition(
            bookingId: widget.bookingId,
            milestone: eval.currentStage,
            workerName: widget.workerName,
            arrivalOtp: _arrivalOtp,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _shadowMode = match.mode;
        _activeOsmRoute = match.activeOsmRoute;
        _cubicBezierBridge = match.cubicBezierShortcutBridge;
        _remainingDistanceM = match.remainingRouteMeters;
        _etaMinutes = etaMins;
      });

      if (_cameraAutoFollow) {
        _mapController.move(match.matchedPosition, _mapController.camera.zoom);
      }
    }
  }

  Future<void> _fetchHeadingBiasedRoute(LatLng origin, double heading) async {
    _isFetchingRoute = true;
    try {
      final OsmShadowRouteResponse res = await _valhallaRepo.fetchShadowRoute(
        bookingId: widget.bookingId,
        workerPosition: origin,
        destination: widget.jobDestination,
        workerHeadingDeg: heading,
      );
      if (mounted) {
        _viterbiMatcher.resetRouteMemory();
        setState(() {
          _masterOsmRoute = res.polyline;
          _activeOsmRoute = res.polyline;
        });
      }
    } finally {
      _isFetchingRoute = false;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _rtdbSub?.cancel();
    _firestoreSub?.cancel();
    _otpSub?.cancel();
    _freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LatLng center = _displayPos ?? widget.jobDestination;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15.6,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _cameraAutoFollow) {
                  setState(() => _cameraAutoFollow = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kelasagara.app',
              ),
              PolylineLayer(
                polylines: [
                  if (_activeOsmRoute.length >= 2)
                    Polyline(
                      points: _activeOsmRoute,
                      strokeWidth: 5.5,
                      color: const Color(0xFF059669),
                    ),
                  if (_cubicBezierBridge.length >= 2)
                    Polyline(
                      points: _cubicBezierBridge,
                      strokeWidth: 4.5,
                      color: const Color(0xFF2563EB),
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.jobDestination,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFFDC2626),
                      size: 42,
                    ),
                  ),
                  if (_displayPos != null)
                    Marker(
                      point: _displayPos!,
                      width: 50,
                      height: 50,
                      child: Transform.rotate(
                        angle: _displayBearing * math.pi / 180.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _isMockLocationFlagged
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF111827),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 8),
                            ],
                          ),
                          child: const Icon(
                            Icons.two_wheeler,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                  ),
                ],
              ),
            ],
          ),

          // Top Enterprise Telemetry Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildEnterpriseHeaderCard(),
                  if (_geofenceBanner != null) ...[
                    const SizedBox(height: 8),
                    _buildGeofenceBanner(_geofenceBanner!),
                  ],
                ],
              ),
            ),
          ),

          // Re-Center Auto-Follow Floating Pill
          if (!_cameraAutoFollow && _displayPos != null)
            Positioned(
              right: 16,
              bottom: 185,
              child: FloatingActionButton.extended(
                backgroundColor: const Color(0xFF111827),
                onPressed: () {
                  setState(() => _cameraAutoFollow = true);
                  _mapController.move(_displayPos!, 16.0);
                },
                icon: const Icon(Icons.my_location, color: Colors.white, size: 18),
                label: const Text(
                  'Re-center',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),

          // Bottom OTP & Lifecycle Card
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBottomOtpCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterpriseHeaderCard() {
    final bool isDisconnected = _workerConnState == 'disconnected';
    final bool isGully = _shadowMode == ShadowTrackingMode.googleShortcutGlide;

    final (Color badgeColor, String statusText) = _isMockLocationFlagged
        ? (const Color(0xFFDC2626), 'GPS Tamper Detected • Verification Paused')
        : isDisconnected
            ? (
                const Color(0xFFEF4444),
                'Worker Signal Lost • Last seen ${_secondsSinceLastPing}s ago'
              )
            : _isDeadReckoning
                ? (
                    const Color(0xFFF59E0B),
                    'Tunnel/Signal Prediction Active (60fps)'
                  )
                : isGully
                    ? (
                        const Color(0xFF2563EB),
                        'Google Maps Gully Shortcut • Live 60fps'
                      )
                    : (
                        const Color(0xFF059669),
                        'Viterbi Road-Locked • Live 60fps'
                      );

    final String distKm = (_remainingDistanceM / 1000.0).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        statusText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.workerName} is on the way',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$distKm km remaining • Ping ${_secondsSinceLastPing}s ago',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '$_etaMinutes',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'MINS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeofenceBanner(BilingualNotificationPayload alert) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${alert.titleKn} • ${alert.titleEn}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF065F46),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            alert.bodyKn,
            style: const TextStyle(fontSize: 12, color: Color(0xFF047857)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomOtpCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isOtpLocked) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_clock_rounded, color: Color(0xFFDC2626), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'OTP ಲಾಕ್ ಆಗಿದೆ ಅಥವಾ ಹೊಸ ಕೋಡ್ ಅಗತ್ಯವಿದೆ • OTP Locked / Needs Reissue',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF991B1B)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final res = await BookingService.instance.regenerateArrivalOtp(bookingId: widget.bookingId);
                        if (res.success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('ಹೊಸ OTP ರಚಿಸಲಾಗಿದೆ: ${res.newOtp}')),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('ಹೊಸ OTP ರಚಿಸಿ • Regenerate OTP', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Arrival Handshake OTP',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                      Text(
                        'ಕೆಲಸ ಪ್ರಾರಂಭಿಸಲು ಈ ಕೋಡ್ ನೀಡಿ',
                        style: TextStyle(fontSize: 12, color: Color(0xFF3B82F6)),
                      ),
                    ],
                  ),
                  Text(
                    _arrivalOtp,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Color(0xFF1D4ED8),
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
}
