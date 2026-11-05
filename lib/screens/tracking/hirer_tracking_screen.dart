// lib/screens/tracking/hirer_tracking_screen.dart
// Production-grade 60fps Hirer Tracking Screen.
// Features CartoDB Voyager Retina tiles, dual-mode shadow tracking (OSM road-locked vs Google shortcut glide),
// 60fps Cubic Hermite kinematics, and dynamic emerald/blue route tinting.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';
import '../../features/tracking/controllers/hirer_osm_tracking_controller.dart';
import '../../features/tracking/domain/gmaps_osm_shadow_engine.dart';
import '../../features/tracking/data/models/tracking_state_model.dart';
import '../../features/tracking/presentation/widgets/live_eta_header_card.dart';
import '../../features/tracking/presentation/widgets/tracking_bottom_sheet.dart';
import '../../services/navigation/map_tile_configuration.dart';
import '../chat/chat_screen.dart';

class HirerTrackingScreen extends StatefulWidget {
  final String bookingId;
  final LatLng? hirerLocation;
  final LatLng? initialWorkerLocation;
  final String workerName;
  final String workerPhone;
  final String workerCategory;

  // Additional optional parameters for backward compatibility
  final String? jobId;
  final String? workerId;
  final double? destLat;
  final double? destLng;
  final String? jobAddress;
  final String? jobTitle;
  final String? currentBookingStatus;
  final HirerOsmTrackingController? controller;

  const HirerTrackingScreen({
    super.key,
    required this.bookingId,
    this.hirerLocation,
    this.initialWorkerLocation,
    this.workerName = 'Service Partner',
    this.workerPhone = '',
    this.workerCategory = 'Specialist',
    this.jobId,
    this.workerId,
    this.destLat,
    this.destLng,
    this.jobAddress,
    this.jobTitle,
    this.currentBookingStatus,
    this.controller,
  });

  @override
  State<HirerTrackingScreen> createState() => _HirerTrackingScreenState();
}

class _HirerTrackingScreenState extends State<HirerTrackingScreen>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late final HirerOsmTrackingController _controller;
  late final AnimationController _glideController;
  late final Animation<double> _glideCurve;

  bool _followWorker = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    _glideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _glideCurve = CurvedAnimation(
      parent: _glideController,
      curve: Curves.easeOutCubic,
    );

    final resolvedHirerLoc = widget.hirerLocation ??
        ((widget.destLat != null &&
                widget.destLng != null &&
                widget.destLat != 0.0)
            ? LatLng(widget.destLat!, widget.destLng!)
            : const LatLng(12.9716, 77.5946));

    _controller = widget.controller ??
        HirerOsmTrackingController(
          bookingId: widget.bookingId,
          initialHirerDestination: resolvedHirerLoc,
          initialWorkerFallback: widget.initialWorkerLocation,
          initialWorkerName: widget.workerName,
          initialWorkerPhone: widget.workerPhone,
          initialWorkerCategory: widget.workerCategory,
        );

    _glideController.addListener(() {
      _controller.onAnimationTick(_glideCurve.value);
    });

    _controller.onTriggerFrameInterpolation = () {
      if (!mounted) return;
      _glideController.forward(from: 0.0);
    };

    _controller.initialize();
  }

  void _recenterCameraBounds() {
    final s = _controller.state;
    final pts = <LatLng>[
      s.workerAnimatedPosition,
      s.hirerDestination,
      ...s.activeRemainingPolyline,
    ];
    if (pts.length < 2) return;

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(54, 140, 54, 320),
        maxZoom: 17.5,
      ),
    );
    setState(() => _followWorker = true);
  }

  Future<void> _callWorker(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanPhone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: cleanPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openChat() {
    final wId = widget.workerId;
    if (wId == null || wId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          workerName: widget.workerName,
          jobTitle: widget.jobTitle ?? 'Job Service',
          otherUserId: wId,
          jobId: widget.jobId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _glideController.dispose();
    _controller.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final state = _controller.state;
          final isShortcutGlide =
              _controller.glideMode == TrackingGlideMode.googleShortcutGlide;

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: state.phase == JourneyLifecyclePhase.accepted
                      ? state.hirerDestination
                      : state.workerAnimatedPosition,
                  initialZoom: 15.5,
                  onPositionChanged: (_, hasGesture) {
                    if (hasGesture && _followWorker) {
                      setState(() => _followWorker = false);
                    }
                  },
                ),
                children: [
                  // Swiggy/Uber-grade resilient OpenStreetMap raster tiles
                  Builder(builder: (context) {
                    final mapConfig =
                        MapTileConfiguration.instance.validateConfiguration();
                    return TileLayer(
                      urlTemplate: mapConfig.urlTemplate ??
                          MapTileConfiguration.osmTileUrlTemplate,
                      subdomains: mapConfig.subdomains,
                      userAgentPackageName: 'com.kelasagaara.kelasagaara',
                      retinaMode: RetinaMode.isHighDensity(context),
                      maxZoom: 19,
                    );
                  }),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        '© OpenStreetMap contributors',
                        onTap: () => launchUrl(
                          Uri.parse('https://openstreetmap.org/copyright'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),

                  // Layer 1: Actual Driven Google Maps Breadcrumb Trail (Muted Slate)
                  if (state.traversedPolyline.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: state.traversedPolyline,
                          strokeWidth: 4.5,
                          color: const Color(0xFF64748B).withValues(alpha: 0.55),
                        ),
                      ],
                    ),

                  // Layer 2: Active Remaining Route (Always connected to Worker via Elastic Bridge)
                  if (state.activeRemainingPolyline.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: state.activeRemainingPolyline,
                          strokeWidth: 9.0,
                          color: const Color(0xFF064E3B),
                        ),
                        Polyline(
                          points: state.activeRemainingPolyline,
                          strokeWidth: 5.5,
                          color: isShortcutGlide
                              ? const Color(0xFF3B82F6) // Blue tint while adapting to Google Maps shortcut
                              : const Color(0xFF10B981), // Emerald when locked on OSM corridor
                        ),
                      ],
                    ),

                  // Layer 3: Hirer Destination & 60fps Hermite-Interpolated Worker Marker
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: state.hirerDestination,
                        width: 48,
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.home_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      if (state.hasActiveWorkerPosition)
                        Marker(
                          point: state.workerAnimatedPosition,
                          width: 58,
                          height: 58,
                        child: Transform.rotate(
                          angle: state.workerBearing * (math.pi / 180.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.45),
                                  blurRadius: 14,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.two_wheeler_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Align(
                alignment: Alignment.topCenter,
                child: LiveEtaHeaderCard(
                  state: state,
                  onBack: () => Navigator.of(context).maybePop(),
                  onRecenter: _recenterCameraBounds,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: TrackingBottomSheet(
                  state: state,
                  onCallWorker: () => _callWorker(
                    state.workerPhone.isNotEmpty
                        ? state.workerPhone
                        : widget.workerPhone,
                  ),
                  onMessageTap: _openChat,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
