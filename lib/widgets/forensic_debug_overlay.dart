// lib/widgets/forensic_debug_overlay.dart
// V900 Forensic Debug Overlay — Diagnostic inspection tool for GPS,
// route progress, camera follow, and navigation state.
// Debug-only, collapsible, and non-intrusive.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/navigation_health.dart';
import '../services/navigation_engine.dart';
import '../providers/journey_provider.dart';

class ForensicDebugOverlay extends StatefulWidget {
  final JourneyProvider provider;
  final NavState? navState;
  final bool followWorker;
  final double currentZoom;
  final LatLng? displayPos;
  final double displayHdg;

  const ForensicDebugOverlay({
    super.key,
    required this.provider,
    required this.navState,
    required this.followWorker,
    required this.currentZoom,
    this.displayPos,
    this.displayHdg = 0.0,
  });

  @override
  State<ForensicDebugOverlay> createState() => _ForensicDebugOverlayState();
}

class _ForensicDebugOverlayState extends State<ForensicDebugOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final nav = widget.navState;
    final prov = widget.provider;
    final workerLoc = prov.workerLocation;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      right: 12,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _expanded ? 280 : 86,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: nav?.isSnapped == true ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: nav != null ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'DEBUG',
                        style: GoogleFonts.firaCode(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const Divider(color: Colors.white24, height: 12),
              _sectionHeader('PHASE 26 DIAGNOSTICS'),
              _dataRow('Booking', prov.bookingId != null && prov.bookingId!.isNotEmpty ? 'VALID' : 'INVALID'),
              _dataRow('Destination', prov.destination != null ? 'VALID' : 'INVALID'),
              _dataRow('Map Provider', prov.health.activeMapProvider),
              _dataRow('Map Config', prov.health.mapStatus.isReady ? 'READY' : 'MISSING'),
              _dataRow('GPS Service', prov.health.gpsStatus == GpsStatus.serviceDisabled ? 'OFF' : 'ON'),
              _dataRow('GPS Permission', prov.health.gpsStatus == GpsStatus.permissionDenied ? 'DENIED' : 'PRECISE'),
              _dataRow('GPS', prov.health.gpsStatus.displayName),
              _dataRow('GPS Accuracy', prov.health.gpsAccuracyMeters != null ? '${prov.health.gpsAccuracyMeters!.round()}m' : '—'),
              _dataRow('GPS Age', '${prov.health.gpsAgeMs ?? prov.secSinceUpdate * 1000} ms'),
              _dataRow('Route Provider', prov.health.activeRouteProvider),
              _dataRow('Route Config', prov.routeServerConfigured ? 'READY' : 'MISSING'),
              _dataRow('Route', prov.health.routeStatus.displayName),
              _dataRow('Route Latency', prov.health.routeLatencyMs != null ? '${prov.health.routeLatencyMs} ms' : '—'),
              _dataRow('Navigation', prov.health.navigationStatus.displayName),
              _dataRow('Session', prov.navigationSessionId.isNotEmpty ? prov.navigationSessionId : '—'),
              _dataRow('Request', prov.activeRequestId.isNotEmpty ? prov.activeRequestId : '—'),

              const SizedBox(height: 6),
              _sectionHeader('GPS TELEMETRY'),
              _dataRow('Raw LatLng', nav != null
                  ? '${nav.rawPosition.latitude.toStringAsFixed(4)}, ${nav.rawPosition.longitude.toStringAsFixed(4)}'
                  : (workerLoc != null
                      ? '${workerLoc.latitude.toStringAsFixed(4)}, ${workerLoc.longitude.toStringAsFixed(4)}'
                      : 'None')),
              _dataRow('Accuracy', nav != null ? '${nav.accuracy.round()}m' : '${workerLoc?.accuracy.round() ?? 0}m'),
              _dataRow('Speed', '${nav?.speedKmh.round() ?? 0} km/h (raw: ${(workerLoc?.speed ?? 0).toStringAsFixed(1)})'),
              _dataRow('Heading', '${(nav?.heading ?? widget.displayHdg).round()}°'),
              _dataRow('Freshness', prov.lastSeenText),

              const SizedBox(height: 6),
              _sectionHeader('ROUTE & PROGRESS'),
              _dataRow('Provider', prov.route?.provider ?? prov.route?.routingEngine ?? 'None'),
              _dataRow('Road Dist Rem', nav != null ? '${nav.remainingDistanceM.round()}m' : prov.distanceText),
              _dataRow('Road ETA', nav?.etaString ?? prov.etaText),
              _dataRow('Snapped', nav?.isSnapped == true ? 'YES (snapped)' : 'NO (raw)'),
              _dataRow('Off-Route', nav?.isOffRoute == true ? 'OFF-ROUTE' : 'ON-ROUTE'),
              _dataRow('Step', '${nav?.currentStepIndex ?? 0}/${prov.route?.steps.length ?? 0}'),

              const SizedBox(height: 6),
              _sectionHeader('CAMERA & GESTURES'),
              _dataRow('Follow Mode', widget.followWorker ? 'ENABLED (auto)' : 'FREE (user pan)'),
              _dataRow('Zoom Level', widget.currentZoom.toStringAsFixed(1)),

              const SizedBox(height: 6),
              _sectionHeader('STATE MACHINE'),
              _dataRow('NavPhase', prov.phase.name),
              _dataRow('JourneyStatus', prov.status.name),
              _dataRow('Arrived', nav?.hasArrived == true ? 'YES' : 'NO'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        title,
        style: GoogleFonts.firaCode(
          color: const Color(0xFF60A5FA),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.firaCode(color: Colors.white60, fontSize: 9),
          ),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.firaCode(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
