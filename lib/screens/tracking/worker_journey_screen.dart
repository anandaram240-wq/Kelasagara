// lib/screens/tracking/worker_journey_screen.dart
// PHASE 3 REDESIGN — Google Maps-style turn-by-turn navigation for worker.
// Features: heading-up map, arrow marker, split polyline (grey/blue),
// live instruction card, next-step preview, rerouting banner,
// speed badge, ETA bar, step list bottom sheet.
// NO fake GPS. NO simulation.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/journey_provider.dart';
import '../../models/journey_state.dart';
import '../../services/navigation_engine.dart';
import '../../services/journey_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/navigation_health.dart';
import '../../services/navigation/map_tile_configuration.dart';
import '../../widgets/forensic_debug_overlay.dart';
import '../../features/tracking/services/google_maps_navigation_launcher.dart';
import '../../features/tracking/presentation/widgets/worker_otp_verification_sheet.dart';
import '../../features/tracking/domain/arrival_eligibility_policy.dart';

class WorkerJourneyScreen extends StatefulWidget {
  final String bookingId;
  final String workerId;
  final String hirerId;
  final String jobId;         // Phase 4: for RTDB tracking identity
  final double destLat;
  final double destLng;
  final String jobAddress;
  final String jobTitle;
  final String workerName;
  final String currentBookingStatus;

  const WorkerJourneyScreen({
    super.key,
    required this.bookingId,
    required this.workerId,
    required this.hirerId,
    required this.jobId,
    required this.destLat,
    required this.destLng,
    required this.jobAddress,
    required this.jobTitle,
    required this.workerName,
    required this.currentBookingStatus,
  });

  @override
  State<WorkerJourneyScreen> createState() => _WorkerJourneyScreenState();
}

class _WorkerJourneyScreenState extends State<WorkerJourneyScreen>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();

  // ── Smooth 60fps marker animation ─────────────────────────────────────────
  late final AnimationController _markerAnim;
  late Animation<double> _latAnim, _lngAnim, _hdgAnim;
  LatLng _displayPos  = const LatLng(0, 0);
  LatLng _prevPos     = const LatLng(0, 0);
  double _displayHdg  = 0;
  double _prevHdg     = 0;
  // D4 Fix: Track the last heading used for map rotation.
  // Map rotate() is only called when heading change exceeds this threshold.
  // This eliminates continuous jitter from 1Hz NavState heading updates
  // when the worker is travelling in a straight line.
  double _lastMapHeading = 0;
  static const double _mapRotateThresholdDeg = 5.0;

  bool _followWorker        = true;
  bool _isStarting          = false;
  bool _initialGpsCentered  = false;
  // CRITICAL: MapController throws StateError if accessed before FlutterMap mounts.
  // In release mode this shows as a grey screen (no red error overlay).
  // All _mapCtrl.camera / move / rotate calls MUST check this flag first.
  bool _isMapReady          = false;

  // Re-center timer
  Timer? _recenterTimer;

  // Nav stream subscription
  StreamSubscription<NavState>? _navSub;

  @override
  void initState() {
    super.initState();
    _markerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final prov = context.read<JourneyProvider>();
    await prov.initWorker(
      bookingId:            widget.bookingId,
      workerId:             widget.workerId,
      hirerId:              widget.hirerId,
      jobId:                widget.jobId,       // Phase 4: RTDB identity
      destLat:              widget.destLat,
      destLng:              widget.destLng,
      workerName:           widget.workerName,
      jobTitle:             widget.jobTitle,
      currentBookingStatus: widget.currentBookingStatus,
    );
    // Subscribe to NavEngine stream
    _navSub = NavigationEngine.instance.stream.listen(_onNavState);
  }

  void _onNavState(NavState state) {
    if (!mounted) return;
    final newPos = state.snappedPosition;
    final newHdg = state.heading;

    // V900: Follow camera on NavState updates (1 Hz), strictly preserving user's current zoom!
    // Guard: map controller throws StateError before FlutterMap is mounted.
    if (_isMapReady && _followWorker && newPos.latitude != 0) {
      final curZoom = _mapCtrl.camera.zoom;
      final targetZoom = (curZoom.isNaN || curZoom < 5.0) ? 16.5 : curZoom;
      _mapCtrl.move(newPos, targetZoom);
      // D4 Fix: Only rotate the map when heading changes by more than the threshold.
      // Calling rotate() on every 1Hz NavState update caused visible map jitter
      // when the worker was travelling in a straight line (heading barely changing).
      // Camera position is still updated every tick to keep the marker centred.
      final hdgDelta = (newHdg - _lastMapHeading).abs();
      if (hdgDelta > _mapRotateThresholdDeg) {
        _mapCtrl.rotate(-newHdg);
        _lastMapHeading = newHdg;
      }
    }

    if (_prevPos.latitude == 0) {
      setState(() { _displayPos = newPos; _displayHdg = newHdg; });
      _prevPos = newPos; _prevHdg = newHdg;
      return;
    }
    _latAnim = Tween<double>(begin: _prevPos.latitude,  end: newPos.latitude)
        .animate(CurvedAnimation(parent: _markerAnim, curve: Curves.easeInOut));
    _lngAnim = Tween<double>(begin: _prevPos.longitude, end: newPos.longitude)
        .animate(CurvedAnimation(parent: _markerAnim, curve: Curves.easeInOut));
    _hdgAnim = Tween<double>(begin: _prevHdg,           end: newHdg)
        .animate(CurvedAnimation(parent: _markerAnim, curve: Curves.easeInOut));
    _markerAnim.removeListener(_onAnim);
    _markerAnim.addListener(_onAnim);
    _markerAnim.forward(from: 0);
    _prevPos = newPos; _prevHdg = newHdg;
  }

  void _onAnim() {
    if (!mounted) return;
    // V900: _onAnim ONLY updates the marker widget smoothly.
    // NEVER call _mapCtrl.move() or _mapCtrl.rotate() inside _onAnim()!
    setState(() {
      _displayPos = LatLng(_latAnim.value, _lngAnim.value);
      _displayHdg = _hdgAnim.value;
    });
  }

  @override
  void dispose() {
    _navSub?.cancel();
    _markerAnim.dispose();
    _mapCtrl.dispose();
    _recenterTimer?.cancel();
    super.dispose();
  }

  void _onUserInteractedWithMap() {
    if (_followWorker) {
      setState(() => _followWorker = false);
    }
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _followWorker = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JourneyProvider>(
      builder: (ctx, prov, _) {
        // When JourneyService GPS arrives BEFORE NavEngine starts,
        // center map ONCE on worker position
        if (_displayPos.latitude == 0 && _followWorker && prov.workerLatLng != null && !_initialGpsCentered) {
          _initialGpsCentered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isMapReady) _mapCtrl.move(prov.workerLatLng!, 16.0);
          });
        }
        return StreamBuilder<NavState>(
          stream: NavigationEngine.instance.stream,
          initialData: NavigationEngine.instance.current,
          builder: (context, snapshot) {
            final nav = snapshot.data;
            return _buildScaffold(prov, nav);
          },
        );
      },
    );
  }

  Widget _buildScaffold(JourneyProvider prov, NavState? nav) {
    final dest  = LatLng(widget.destLat, widget.destLng);
    final phase = prov.phase;

    final workerPos = prov.workerLatLng ?? nav?.snappedPosition ?? nav?.rawPosition;
    final directDistM = workerPos != null && workerPos.latitude != 0 && dest.latitude != 0
        ? const Distance().as(LengthUnit.Meter, workerPos, dest)
        : null;
    final isWithin75m = ArrivalEligibilityPolicy.canWorkerEnterOtp(
      status: prov.status == JourneyStatus.arrived ? 'arrived' : widget.currentBookingStatus,
      distanceMeters: directDistM,
      accuracyMeters: nav?.accuracy,
      isSeed: false,
    );

    // Auto-record arrival handshake when within canonical 75m geofence
    if (isWithin75m &&
        prov.status != JourneyStatus.arrived &&
        prov.status != JourneyStatus.workStarted &&
        prov.status != JourneyStatus.completionRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        prov.markArrived();
      });
    }

    // Arrived = Within 75m doorstep geofence OR NavEngine detected OR booking status says so
    final arrived = isWithin75m ||
        (nav?.hasArrived ?? false) ||
        phase == NavigationPhase.arrived ||
        prov.status == JourneyStatus.arrived ||
        prov.status == JourneyStatus.workStarted;

    // Top card: instruction when navigating, pre-journey when not
    final showInstruction = phase.isActive;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(children: [

        // ── MAP ───────────────────────────────────────────────────────────────
        _buildMap(prov, nav, dest),

        // ── TOP card ──────────────────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12, right: 12,
          child: showInstruction
              ? _buildInstructionCard(prov, nav)
              : _buildPreJourneyCard(prov),
        ),

        // ── Rerouting banner (overlays instruction card) ───────────────────────
        if (nav?.isRerouting == true || phase == NavigationPhase.rerouting)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12, right: 12,
            child: _buildReroutingBanner(nav?.rerouteMessage),
          ),

        // ── Re-center FAB ─────────────────────────────────────────────────────
        if (!_followWorker)
          Positioned(
            bottom: 200, right: 16,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: () {
                setState(() => _followWorker = true);
                final centerPos = _displayPos.latitude != 0
                    ? _displayPos
                    : (prov.workerLatLng ?? dest);
                if (centerPos.latitude != 0 && _isMapReady) {
                  final curZoom = _mapCtrl.camera.zoom;
                  final targetZoom = (curZoom < 14.0 || curZoom > 18.0) ? 16.5 : curZoom;
                  _mapCtrl.move(centerPos, targetZoom);
                  _mapCtrl.rotate(-_displayHdg);
                  _lastMapHeading = _displayHdg; // D4 Fix: sync threshold after explicit recenter
                }
              },
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location_rounded, color: Color(0xFF3B82F6)),
            ),
          ),

        // ── Forensic Debug Overlay (visible in debug builds) ─────────────────
        ForensicDebugOverlay(
          provider: prov,
          navState: nav,
          followWorker: _followWorker,
          // CRITICAL: _mapCtrl.camera throws StateError before map is ready.
          // Pass 0.0 until onMapReady fires — overlay shows "0.0" briefly, safe.
          currentZoom: _isMapReady ? _mapCtrl.camera.zoom : 0.0,
          displayPos: _displayPos,
          displayHdg: _displayHdg,
        ),

        // ── Step list button ──────────────────────────────────────────────────
        if (phase.isActive && (nav?.remainingPolyline.isNotEmpty ?? false))
          Positioned(
            bottom: 200, left: 16,
            child: FloatingActionButton.small(
              heroTag: 'steps',
              onPressed: () => _showStepSheet(context, nav),
              backgroundColor: const Color(0xFF1E293B),
              child: const Icon(Icons.list_alt_rounded, color: Colors.white),
            ),
          ),

        // ── BOTTOM bar — driven entirely by NavigationPhase & BootstrapState ─
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _buildBottomBar(prov, nav, phase, arrived),
        ),
      ]),
    );
  }

  /// Single authoritative bottom bar selector.
  /// The ONLY place where phase → widget mapping is decided.
  Widget _buildBottomBar(JourneyProvider prov, NavState? nav,
      NavigationPhase phase, bool arrived) {
    // Priority order (most specific first)
    if (prov.status == JourneyStatus.completionRequested) {
      return _buildCompletionPendingBar();
    }
    if (arrived) {
      return _buildArrivedBar(prov);
    }
    switch (phase) {
      case NavigationPhase.routeError:
      case NavigationPhase.error:
      case NavigationPhase.permissionDenied:
      case NavigationPhase.gpsDisabled:
      case NavigationPhase.unauthorized:
        return _buildRouteErrorBar(prov);
      case NavigationPhase.routeRequesting:
      case NavigationPhase.requestingRoute:
      case NavigationPhase.validatingRoute:
      case NavigationPhase.locationAcquiring:
      case NavigationPhase.requestingGps:
      case NavigationPhase.validatingGps:
      case NavigationPhase.loadingBooking:
      case NavigationPhase.validatingDestination:
        return _buildRouteLoadingBar(prov);
      case NavigationPhase.routeReady:
      case NavigationPhase.routePreviewReady:
        return _buildRoutePreviewBar(prov);
      case NavigationPhase.navigationStarting:
      case NavigationPhase.startingJourney:
      case NavigationPhase.navigating:
      case NavigationPhase.gpsLost:
      case NavigationPhase.gpsDegraded:
      case NavigationPhase.networkDegraded:
      case NavigationPhase.offRoute:
      case NavigationPhase.rerouting:
      case NavigationPhase.routeRecalculating:
      case NavigationPhase.nearDestination:
      case NavigationPhase.approaching:
      case NavigationPhase.arrivalPending:
        return _buildNavBar(prov, nav);
      case NavigationPhase.arrived:
        return _buildArrivedBar(prov);
      default:
        return _buildStartBar(prov);
    }
  }

  // ── Map with all layers ───────────────────────────────────────────────────
  Widget _buildMap(JourneyProvider prov, NavState? nav, LatLng dest) {
    final passedPoly    = nav?.passedPolyline ?? const [];
    final remainingPoly = nav?.remainingPolyline ?? prov.routePolyline;

    // Worker position: NavEngine smooth position (priority) OR JourneyService raw GPS
    // This fixes the regression where marker disappeared before NavEngine started.
    LatLng? workerPos;
    if (_displayPos.latitude != 0) {
      workerPos = _displayPos;                            // NavEngine running → smooth
    } else if (prov.workerLatLng != null) {
      workerPos = prov.workerLatLng;                      // JourneyService GPS → raw but correct
    }
    final showWorker = workerPos != null;

    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        // Fix 4: light grey background shows while tiles load (no pure grey flash)
        backgroundColor: const Color(0xFFE8ECF0),
        initialCenter:   workerPos ?? dest,
        initialZoom:     16.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        // CRITICAL: Set _isMapReady so all MapController calls are safe.
        // MapController throws StateError if .camera/.move/.rotate is called before this fires.
        onMapReady: () {
          if (mounted) setState(() => _isMapReady = true);
        },
        onMapEvent: (event) {
          // If the event source is NOT programmatic map controller,
          // it is a user gesture (pan, pinch-zoom, fling, double-tap, etc.)
          if (event.source != MapEventSource.mapController &&
              event.source != MapEventSource.nonRotatedSizeChange) {
            _onUserInteractedWithMap();
          }
        },
      ),
      children: [
        Builder(builder: (context) {
          final mapConfig = MapTileConfiguration.instance.validateConfiguration();
          return TileLayer(
            urlTemplate: mapConfig.urlTemplate ??
                MapTileConfiguration.osmTileUrlTemplate,
            subdomains: mapConfig.subdomains,
            userAgentPackageName: 'com.kelasagaara.kelasagaara',
            keepBuffer: 4,   // keep more tiles in memory during zoom transitions
            panBuffer: 2,    // pre-load tiles in pan direction
            errorTileCallback: (tile, error, _) =>
                debugPrint('[Map] Tile load error: $error'),
          );
        }),

        // Passed route (grey)
        if (passedPoly.length > 1)
          PolylineLayer(polylines: [
            Polyline(
              points:       passedPoly,
              strokeWidth:  5,
              color:        Colors.grey.withAlpha(100),
            ),
          ]),

        // Remaining route (blue)
        if (remainingPoly.length > 1)
          PolylineLayer(polylines: [
            Polyline(
              points:       remainingPoly,
              strokeWidth:  7,
              color:        const Color(0xFF3B82F6),
              borderColor:  const Color(0xFF1D4ED8),
              borderStrokeWidth: 1.5,
            ),
          ]),

        // Destination marker
        MarkerLayer(markers: [
          Marker(
            point:  dest,
            width:  40, height: 50,
            child:  const Icon(Icons.location_on_rounded,
                      color: Color(0xFFEF4444), size: 40),
          ),
        ]),

        // Worker arrow marker — shows from JourneyService GPS immediately,
        // switches to NavEngine smooth position when NavEngine starts
        if (showWorker)
          MarkerLayer(markers: [
            Marker(
              point:  workerPos,
              width:  44, height: 44,
              child:  Transform.rotate(
                angle: _displayHdg * math.pi / 180,
                child: const _ArrowMarker(),
              ),
            ),
          ]),
      ],
    );
  }

  // ── Instruction card (Google Maps style) ─────────────────────────────────
  Widget _buildInstructionCard(JourneyProvider prov, NavState? nav) {
    final step     = nav?.currentStep;
    final nextStep = nav?.nextStep;
    final distToTurn = nav?.distanceToNextTurnM ?? 0;

    // Smart fallback chain:
    // 1. NavEngine live step (when GPS is flowing through NavEngine)
    // 2. First step from fetched route steps (pre-NavEngine GPS fix)
    // 3. "Finding route..." only if actually loading
    // 4. "Follow the blue route" if route is ready but no steps
    final fallbackStep = prov.route?.steps.isNotEmpty == true ? prov.route!.steps[0] : null;
    final displayStep  = step ?? fallbackStep;

    final instructionText = displayStep?.instruction
        ?? (prov.isLoadingRoute ? 'Finding the best route...' : 'Follow the blue route');
    final instructionKn   = displayStep?.instructionKn ?? '';
    final displayIcon     = displayStep?.maneuverType.icon ?? Icons.navigation_rounded;
    final displayDist     = step != null ? distToTurn
        : (fallbackStep?.distanceM.toDouble() ?? 0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 12)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Current step
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: prov.isLoadingRoute
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(displayIcon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(instructionText,
                  style: GoogleFonts.sora(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w800),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                if (instructionKn.isNotEmpty)
                  Text(instructionKn,
                    style: GoogleFonts.notoSansKannada(color: Colors.white60,
                      fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )),
            const SizedBox(width: 8),
            if (displayDist > 0) Column(children: [
              Text(_formatDist(displayDist),
                style: GoogleFonts.sora(color: const Color(0xFF60A5FA),
                  fontSize: 18, fontWeight: FontWeight.w900)),
              Text(displayDist < 1000 ? 'm' : 'km',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ]),
        ),

        // Next step preview
        if (nextStep != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            decoration: const BoxDecoration(
              color: Color(0x22FFFFFF),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 12),
              const SizedBox(width: 8),
              Icon(nextStep.maneuverType.icon, color: Colors.white54, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Then: ${nextStep.instruction}',
                style: GoogleFonts.plusJakartaSans(color: Colors.white54,
                  fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(nextStep.distanceText,
                style: GoogleFonts.sora(color: Colors.white54,
                  fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }

  // ── Pre-journey card ──────────────────────────────────────────────────────
  Widget _buildPreJourneyCard(JourneyProvider prov) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 12)],
      ),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.location_on_rounded, color: Color(0xFF3B82F6), size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.jobTitle,
            style: GoogleFonts.sora(color: Colors.white, fontSize: 13,
              fontWeight: FontWeight.w800), maxLines: 1),
          Text(widget.jobAddress,
            style: GoogleFonts.plusJakartaSans(color: Colors.white54,
              fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        if (prov.isLoadingRoute)
          const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6))),
        if (!prov.isLoadingRoute && prov.routePolyline.isNotEmpty)
          Text(prov.distanceText,
            style: GoogleFonts.sora(color: const Color(0xFF60A5FA),
              fontSize: 13, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  // ── Rerouting banner ──────────────────────────────────────────────────────
  Widget _buildReroutingBanner(String? msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 10),
        Text(msg ?? 'Recalculating...',
          style: GoogleFonts.sora(color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w800)),
      ]),
    );
  }

  // ── Navigation bottom bar ─────────────────────────────────────────────────
  Widget _buildNavBar(JourneyProvider prov, NavState? nav) {
    final eta      = nav?.etaString      ?? prov.etaText;
    final dist     = nav != null
        ? (nav.remainingDistanceM < 1000
            ? '${nav.remainingDistanceM.round()} m'
            : '${(nav.remainingDistanceM / 1000).toStringAsFixed(1)} km')
        : prov.distanceText;
    final speedKmh  = nav?.speedKmh ?? 0;
    final speedText = speedKmh < 2 ? '— km/h' : '${speedKmh.round()} km/h';
    final arrivalT  = nav?.arrivalTimeString ?? prov.route?.arrivalTimeText ?? '';
    final engine    = prov.route?.routingEngine ?? 'valhalla';
    final engineTag = engine == 'valhalla' ? '🗺 Valhalla' : '🗺 OSRM';

    final workerPos = prov.workerLatLng ?? nav?.snappedPosition ?? nav?.rawPosition;
    final directDistM = workerPos != null && workerPos.latitude != 0
        ? const Distance().as(LengthUnit.Meter, workerPos, LatLng(widget.destLat, widget.destLng))
        : null;
    final isWithin75m = ArrivalEligibilityPolicy.canWorkerEnterOtp(
      status: prov.status == JourneyStatus.arrived ? 'arrived' : widget.currentBookingStatus,
      distanceMeters: directDistM,
      accuracyMeters: nav?.accuracy,
      isSeed: false,
    );

    // Only show I've Arrived when actually approaching / arrival detection fired or within 75m
    final showArriveBtn = isWithin75m ||
        prov.showArrivedPrompt ||
        prov.status == JourneyStatus.approaching;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, -4))],
      ),
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ETA / distance / speed row
        Row(children: [
          _statPill(Icons.route_rounded, dist, 'Distance'),
          const SizedBox(width: 10),
          _statPill(Icons.timer_rounded, eta, 'ETA'),
          const SizedBox(width: 10),
          _statPill(Icons.speed_rounded, speedText, 'Speed'),
        ]),
        if (arrivalT.isNotEmpty || true) ...[ // always show arrival time row
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(arrivalT.isNotEmpty ? 'Arriving at $arrivalT' : '',
              style: GoogleFonts.plusJakartaSans(color: AppColors.textLight, fontSize: 11)),
            Text(engineTag,
              style: GoogleFonts.sora(color: const Color(0xFF475569), fontSize: 9,
                fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 12),
        Row(children: [
          if (showArriveBtn) ...[
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _markArrived(prov),
              icon: const Icon(Icons.location_on_rounded, size: 18),
              label: Text("I've Arrived",
                style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )),
            const SizedBox(width: 10),
            _callButton(),
          ] else ...[
            // While navigating (not yet near destination): show Google Maps launch button + call
            Expanded(child: InkWell(
              onTap: () {
                GoogleMapsNavigationLauncher.instance.startBackgroundTrackingAndLaunchGoogleMaps(
                  bookingId: widget.bookingId,
                  workerId: widget.workerId,
                  destination: LatLng(widget.destLat, widget.destLng),
                  destinationLabel: widget.jobAddress,
                );
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.45)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.map_rounded, color: Color(0xFF60A5FA), size: 16),
                  const SizedBox(width: 8),
                  Text('Navigate with Google Maps • ಗೂಗಲ್ ಮ್ಯಾಪ್ಸ್ 🗺',
                    style: GoogleFonts.sora(color: const Color(0xFF93C5FD), fontSize: 12,
                      fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            )),
            const SizedBox(width: 10),
            _callButton(),
          ],
        ]),
      ]),
    );
  }

  // ── Arrived / working bar ─────────────────────────────────────────────────
  Widget _buildArrivedBar(JourneyProvider prov) {
    final isWorking = prov.status == JourneyStatus.workStarted;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(isWorking ? '🔨' : '🏁', style: const TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        Text(isWorking ? 'Work in Progress' : 'You have arrived!',
          style: GoogleFonts.sora(color: Colors.white, fontSize: 20,
            fontWeight: FontWeight.w900)),
        Text(widget.jobAddress,
          style: GoogleFonts.plusJakartaSans(color: AppColors.textLight, fontSize: 12),
          textAlign: TextAlign.center),
        if (isWorking) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF22C55E).withAlpha(100), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_rounded, color: Color(0xFF22C55E), size: 16),
                const SizedBox(width: 8),
                Text('Active Job Session • Performing Tasks',
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFF86EFAC), fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (!isWorking) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: prov.otpVerified ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      prov.otpVerified ? Icons.verified_rounded : Icons.pin_outlined,
                      color: prov.otpVerified ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      prov.otpVerified ? 'Arrival Verified • ಆಗಮನ ಪರಿಶೀಲಿಸಲಾಗಿದೆ' : 'Customer Arrival Code • ಆಗಮನದ ಕೋಡ್',
                      style: GoogleFonts.sora(
                        color: prov.otpVerified ? const Color(0xFF22C55E) : const Color(0xFFFCD34D),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (!prov.otpVerified) ...[
                  Text(
                    'Ask the customer for the 6-digit code shown on their tracking screen\nಕೆಲಸ ಪ್ರಾರಂಭಿಸಲು ಗ್ರಾಹಕರ ಪರದೆಯಲ್ಲಿರುವ 6-ಅಂಕಿಯ ಕೋಡ್ ಕೇಳಿ',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFCBD5E1),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final verified = await WorkerOtpVerificationSheet.show(
                          context,
                          bookingId: widget.bookingId,
                          hirerName: 'Hirer',
                          jobTitle: widget.jobTitle,
                        );
                        if (verified == true) {
                          prov.setOtpVerified();
                        }
                      },
                      icon: const Icon(Icons.vpn_key_rounded, size: 18),
                      label: Text(
                        'Enter Customer OTP 🔑 • OTP ನಮೂದಿಸಿ',
                        style: GoogleFonts.sora(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    '✅ OTP Verified Successfully • Work Authorized',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF86EFAC),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (!prov.otpVerified) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please verify arrival by entering the customer\'s OTP first.'),
                      backgroundColor: Color(0xFFD97706),
                    ),
                  );
                  return;
                }
                _startWork(prov);
              },
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: Text('Start Work 🔨', style: GoogleFonts.sora(
                fontWeight: FontWeight.w800, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: prov.otpVerified ? const Color(0xFF3B82F6) : const Color(0xFF475569),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
        if (isWorking) ...[
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _requestCompletion(prov),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text('Mark Work as Complete', style: GoogleFonts.sora(
                fontWeight: FontWeight.w800, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )),
          const SizedBox(height: 8),
          Text('Hirer will confirm your completion.',
            style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 11),
            textAlign: TextAlign.center),
        ],
      ]),
    );
  }

  // ── Waiting for hirer confirmation bar ────────────────────────────────────
  Widget _buildCompletionPendingBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E3A5F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 32, height: 32,
          child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF3B82F6))),
        const SizedBox(height: 12),
        Text('Waiting for hirer confirmation...',
          style: GoogleFonts.sora(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('The hirer has been notified. Please wait.',
          style: GoogleFonts.sora(color: const Color(0xFF94A3B8), fontSize: 12),
          textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('✅ Your completion request has been sent',
          style: GoogleFonts.sora(color: const Color(0xFF22C55E), fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Pre-journey start bar ─────────────────────────────────────────────────
  Widget _buildStartBar(JourneyProvider prov) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.jobTitle, style: GoogleFonts.sora(color: Colors.white,
              fontSize: 14, fontWeight: FontWeight.w800)),
            Text(widget.jobAddress, style: GoogleFonts.plusJakartaSans(
              color: AppColors.textLight, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (prov.routePolyline.isNotEmpty) ...[
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(prov.distanceText, style: GoogleFonts.sora(
                color: const Color(0xFF60A5FA), fontSize: 16, fontWeight: FontWeight.w900)),
              Text(prov.etaText, style: GoogleFonts.plusJakartaSans(
                color: AppColors.textLight, fontSize: 11)),
            ]),
          ],
        ]),
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final isProvisioning = prov.isVoiceDirectBooking && !prov.isTrackingProvisioned;
          return SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isStarting || isProvisioning) ? null : () => _startJourney(prov),
              icon: _isStarting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : (isProvisioning
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                      : const Icon(Icons.navigation_rounded, size: 20)),
              label: Text(
                _isStarting
                    ? 'Starting...'
                    : (isProvisioning ? 'Setting up tracking...' : 'Start Journey'),
                style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ));
        }),
      ]),
    );
  }

  // ── Route loading bar (phase: locationAcquiring / routeRequesting) ──────────
  // Contract: shown when GPS tracking started, route fetch is in progress.
  Widget _buildRouteLoadingBar(JourneyProvider prov) {
    final isLocating = prov.phase == NavigationPhase.locationAcquiring ||
        prov.bootstrapState == NavigationBootstrapState.requestingLocation ||
        prov.bootstrapState == NavigationBootstrapState.checkingPermission ||
        prov.bootstrapState == NavigationBootstrapState.checkingLocationService;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Row(children: [
        const SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF3B82F6))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isLocating ? 'Finding your location…' : 'Finding road route…',
            style: GoogleFonts.sora(color: Colors.white, fontSize: 14,
              fontWeight: FontWeight.w700)),
          Text(isLocating
              ? 'GPS ಸ್ಥಳ ಹುಡುಕುತ್ತಿದೆ… (10s max)'
              : 'Calculating best route to ${widget.jobTitle}',
            style: GoogleFonts.plusJakartaSans(color: AppColors.textLight, fontSize: 11),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  // ── Route preview bar (phase: routeReady) ────────────────────────────────
  // Contract: shown when route is fetched and validated. Worker sees
  // real distance + ETA before tapping START NAVIGATION.
  Widget _buildRoutePreviewBar(JourneyProvider prov) {
    final engine = prov.route?.routingEngine ?? 'valhalla';
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, -4))],
      ),
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Route summary
        Row(children: [
          const Icon(Icons.flag_rounded, color: Color(0xFF22C55E), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.jobAddress,
            style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 12),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(engine == 'valhalla' ? '🗺 Valhalla' : '🗺 OSRM',
            style: GoogleFonts.sora(color: const Color(0xFF475569), fontSize: 9,
              fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        // Distance / ETA
        Row(children: [
          _statPill(Icons.route_rounded, prov.distanceText, 'Distance'),
          const SizedBox(width: 10),
          _statPill(Icons.timer_rounded, prov.etaText, 'ETA'),
          const SizedBox(width: 10),
          _statPill(Icons.schedule_rounded,
            prov.route?.arrivalTimeText ?? '—', 'Arrival'),
        ]),
        const SizedBox(height: 12),
        // START NAVIGATION button (prominent green)
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startNavigation(prov),
            icon: const Icon(Icons.navigation_rounded, size: 20),
            label: Text('Navigate to Work • ಕೆಲಸದ ಸ್ಥಳಕ್ಕೆ ಹೊರಡಿ',
              style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          )),
        const SizedBox(height: 8),
        // OPEN IN GOOGLE MAPS button (secondary external handoff)
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              GoogleMapsNavigationLauncher.instance.startBackgroundTrackingAndLaunchGoogleMaps(
                bookingId: widget.bookingId,
                workerId: widget.workerId,
                destination: LatLng(widget.destLat, widget.destLng),
                destinationLabel: widget.jobAddress,
              );
            },
            icon: const Icon(Icons.map_rounded, size: 18, color: Color(0xFF60A5FA)),
            label: Text('Open Google Maps Navigation • ಗೂಗಲ್ ಮ್ಯಾಪ್ಸ್ 🗺',
              style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          )),
        const SizedBox(height: 6),
        Text('Route ready • ${prov.route?.steps.length ?? 0} maneuvers',
          style: GoogleFonts.sora(color: const Color(0xFF475569), fontSize: 10)),
      ]),
    );
  }

  // ── Route error bar (phase: routeError / permissionDenied / gpsDisabled) ────
  Widget _buildRouteErrorBar(JourneyProvider prov) {
    final health = prov.health;

    String title = "Couldn't find a road route";
    String subtitle = prov.routeErrorReason ?? 'Routing service unavailable';
    String actionLabel = 'Retry Route';
    VoidCallback onAction = () => prov.retryRoute();
    IconData errorIcon = Icons.wrong_location_rounded;

    if (health.mapStatus.hasError) {
      title = health.mapStatus == MapStatus.configurationError
          ? 'Map Configuration Error'
          : 'Map Tile Error';
      subtitle = health.mapErrorMessage ?? 'CARTO_API_KEY required for map tiles.';
      actionLabel = 'Retry Map';
      onAction = () => prov.retryMap();
      errorIcon = Icons.map_outlined;
    } else if (health.gpsStatus == GpsStatus.permissionDenied ||
        prov.phase == NavigationPhase.permissionDenied ||
        prov.bootstrapState == NavigationBootstrapState.permissionDenied) {
      title = 'Location Permission Required';
      subtitle = 'Please enable location permissions in app settings to navigate.';
      actionLabel = 'App Settings';
      onAction = () async {
        await Geolocator.openAppSettings();
      };
      errorIcon = Icons.location_disabled_rounded;
    } else if (health.gpsStatus == GpsStatus.serviceDisabled ||
        prov.phase == NavigationPhase.gpsDisabled ||
        prov.bootstrapState == NavigationBootstrapState.locationServiceDisabled) {
      title = 'Location Services Off';
      subtitle = 'Turn on device GPS location to start navigation.';
      actionLabel = 'GPS Settings';
      onAction = () async {
        await Geolocator.openLocationSettings();
      };
      errorIcon = Icons.gps_off_rounded;
    } else if (health.gpsStatus == GpsStatus.unavailable ||
        prov.bootstrapState == NavigationBootstrapState.locationTimeout) {
      title = 'Unable to Obtain GPS Fix';
      subtitle = health.gpsErrorMessage ?? "Couldn't acquire GPS fix within 12 seconds. Ensure clear sky view.";
      actionLabel = 'Retry GPS';
      onAction = () => prov.retryGps();
      errorIcon = Icons.gps_not_fixed_rounded;
    } else if (health.routeStatus == RouteStatus.noRoute) {
      title = 'No Road Route Found';
      subtitle = health.routeErrorMessage ?? 'No navigable road route could be found to this destination.';
      actionLabel = 'Retry Route';
      onAction = () => prov.retryRoute();
      errorIcon = Icons.alt_route_rounded;
    } else if (health.routeStatus == RouteStatus.authenticationError) {
      title = 'Routing Authentication Error';
      subtitle = health.routeErrorMessage ?? 'Routing service credentials invalid (401/403).';
      actionLabel = 'Retry Route';
      onAction = () => prov.retryRoute();
      errorIcon = Icons.lock_clock_rounded;
    } else if (health.routeStatus == RouteStatus.timeout ||
        prov.bootstrapState == NavigationBootstrapState.routeTimeout) {
      title = 'Route Calculation Timeout';
      subtitle = health.routeErrorMessage ?? 'Routing request timed out (8s limit).';
      actionLabel = 'Retry Route';
      onAction = () => prov.retryRoute();
      errorIcon = Icons.timer_off_rounded;
    } else if (health.routeStatus == RouteStatus.providerUnavailable ||
        prov.bootstrapState == NavigationBootstrapState.routeUnavailable) {
      title = 'Routing Service Unavailable';
      subtitle = health.routeErrorMessage ?? 'Routing server unreachable or configuration missing.';
      actionLabel = 'Retry Route';
      onAction = () => prov.retryRoute();
      errorIcon = Icons.cloud_off_rounded;
    }

    final isPermOrGps = health.gpsStatus == GpsStatus.permissionDenied ||
        health.gpsStatus == GpsStatus.serviceDisabled ||
        prov.phase == NavigationPhase.permissionDenied ||
        prov.phase == NavigationPhase.gpsDisabled;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, -4))],
      ),
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF7F1D1D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              errorIcon,
              color: const Color(0xFFEF4444), size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
              style: GoogleFonts.sora(color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.w700)),
            Text(subtitle,
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 10),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(actionLabel,
              style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          )),
          if (isPermOrGps) ...[
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => prov.retryBootstrap(),
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: Text('Retry',
                style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )),
          ],
          const SizedBox(width: 10),
          _callButton(),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              GoogleMapsNavigationLauncher.instance.startBackgroundTrackingAndLaunchGoogleMaps(
                bookingId: widget.bookingId,
                workerId: widget.workerId,
                destination: LatLng(widget.destLat, widget.destLng),
                destinationLabel: widget.jobAddress,
              );
            },
            icon: const Icon(Icons.map_rounded, size: 18, color: Color(0xFF60A5FA)),
            label: Text('Open Google Maps Navigation • ಗೂಗಲ್ ಮ್ಯಾಪ್ಸ್ 🗺',
              style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          )),
        const SizedBox(height: 6),
        Text('You can still call the hirer for directions',
          style: GoogleFonts.sora(color: const Color(0xFF6B7280), fontSize: 10),
          textAlign: TextAlign.center),
      ]),
    );
  }

  // ── Step list bottom sheet ────────────────────────────────────────────────
  void _showStepSheet(BuildContext ctx, NavState? nav) {
    final steps = context.read<JourneyProvider>().route?.steps ?? [];
    if (steps.isEmpty) return;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white24,
            borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('All Steps', style: GoogleFonts.sora(color: Colors.white,
            fontSize: 14, fontWeight: FontWeight.w800))),
        Expanded(child: ListView.builder(
          itemCount: steps.length,
          itemBuilder: (_, i) {
            final step = steps[i];
            final isCurrent = i == (nav?.currentStepIndex ?? 0);
            return ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFF3B82F6) : Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(step.maneuverType.icon,
                  color: isCurrent ? Colors.white : Colors.white54, size: 20),
              ),
              title: Text(step.instruction,
                style: GoogleFonts.plusJakartaSans(
                  color: isCurrent ? Colors.white : Colors.white60,
                  fontSize: 12, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500)),
              subtitle: step.instructionKn.isNotEmpty
                  ? Text(step.instructionKn,
                      style: GoogleFonts.notoSansKannada(color: Colors.white38, fontSize: 10))
                  : null,
              trailing: Text(step.distanceText,
                style: GoogleFonts.sora(color: Colors.white38, fontSize: 11)),
            );
          },
        )),
      ]),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _startJourney(JourneyProvider prov) async {
    setState(() => _isStarting = true);
    final ok = await prov.startJourney();
    if (mounted) setState(() => _isStarting = false);
    if (!ok && mounted) {
      if (prov.routeErrorReason == 'PROVISIONING_INCOMPLETE') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
            '⏳ Setting up live tracking session...\nPlease wait a few seconds and try again.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 4),
        ));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
          '❌ Could not start journey.\n'
          '• Make sure GPS is ON\n'
          '• Allow location "While using app" or "Always"\n'
          'Opening settings now...',
        ),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'SETTINGS',
          textColor: Colors.white,
          onPressed: () async {
            await JourneyService.requestPermission();
          },
        ),
      ));
    }
  }

  /// Start turn-by-turn navigation from route preview screen.
  /// Route has already been fetched. NavEngine starts now.
  Future<void> _startNavigation(JourneyProvider prov) async {
    await prov.startNavigation();
  }

  Future<void> _markArrived(JourneyProvider prov) async {
    await prov.markArrived();
  }

  Future<void> _startWork(JourneyProvider prov) async {
    await prov.startWork();
  }

  Future<void> _requestCompletion(JourneyProvider prov) async {
    final result = await prov.requestWorkCompletion();
    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Completion request sent — waiting for hirer confirmation'),
          backgroundColor: Color(0xFF22C55E),
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${result.error}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _callHirer() async {
    // V600 FIX: Previously 'tel:' with no number — silently failed.
    // Now reads hirerPhone from JourneyProvider, with graceful fallback.
    final prov = context.read<JourneyProvider>();
    final phone = prov.hirerPhone;
    if (phone == null || phone.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📞 Hirer phone number not available. Use in-app chat.'),
            backgroundColor: Color(0xFF1E293B),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ── Helper widgets ────────────────────────────────────────────────────────
  Widget _statPill(IconData icon, String value, String label) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Icon(icon, color: const Color(0xFF3B82F6), size: 16),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.sora(color: Colors.white, fontSize: 13,
          fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ]),
    ));
  }

  Widget _callButton() {
    return GestureDetector(
      onTap: _callHirer,
      child: Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.phone_rounded, color: Color(0xFF22C55E), size: 24),
      ),
    );
  }

  String _formatDist(double m) {
    if (m < 1000) return '${m.round()}';
    return (m / 1000).toStringAsFixed(1);
  }
}

// ── Arrow marker (custom painter) ────────────────────────────────────────────
class _ArrowMarker extends StatelessWidget {
  const _ArrowMarker();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(44, 44), painter: _ArrowPainter());
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Shadow
    final shadow = Paint()
      ..color = Colors.black.withAlpha(60)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(cx, cy + 2), 18, shadow);

    // Arrow body
    final fill = Paint()..color = const Color(0xFF3B82F6)..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final path = Path()
      ..moveTo(cx, cy - 18)          // tip (points up = North in un-rotated state)
      ..lineTo(cx + 12, cy + 10)
      ..lineTo(cx, cy + 4)
      ..lineTo(cx - 12, cy + 10)
      ..close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
