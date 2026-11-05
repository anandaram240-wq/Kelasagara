// lib/features/tracking/presentation/widgets/worker_google_maps_bar.dart
// Production-grade action bar for worker journey screen.
// Pre-syncs shared Google polyline into RTDB and triggers Google Maps in 2W/4W mode
// with persistent background telemetry isolate handshake.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../repositories/google_shared_routing_repository.dart';
import '../../services/google_maps_navigation_launcher.dart';

class WorkerGoogleMapsBar extends StatefulWidget {
  final String bookingId;
  final String workerId;
  final LatLng workerCurrentLocation;
  final LatLng hirerDestination;
  final String hirerAddress;

  const WorkerGoogleMapsBar({
    super.key,
    required this.bookingId,
    required this.workerId,
    required this.workerCurrentLocation,
    required this.hirerDestination,
    this.hirerAddress = 'Hirer Location',
  });

  @override
  State<WorkerGoogleMapsBar> createState() => _WorkerGoogleMapsBarState();
}

class _WorkerGoogleMapsBarState extends State<WorkerGoogleMapsBar> {
  final GoogleSharedRoutingRepository _routingRepo =
      GoogleSharedRoutingRepository.instance;
  GoogleMapsTravelMode _selectedMode = GoogleMapsTravelMode.twoWheeler;
  bool _isLaunching = false;

  Future<void> _handleLaunchGoogleMaps() async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    try {
      // 1. Pre-sync shared route to RTDB in background so Hirer sees the same path
      unawaited(
        _routingRepo.fetchOrSyncSharedRoute(
          bookingId: widget.bookingId,
          origin: widget.workerCurrentLocation,
          destination: widget.hirerDestination,
        ),
      );

      // 2. Start foreground GPS isolate & launch native Google Maps app
      await GoogleMapsNavigationLauncher.instance
          .startBackgroundTrackingAndLaunchGoogleMaps(
        bookingId: widget.bookingId,
        workerId: widget.workerId,
        destination: widget.hirerDestination,
        destinationLabel: widget.hirerAddress,
        travelMode: _selectedMode,
      );
    } finally {
      if (mounted) {
        setState(() => _isLaunching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ಲೈವ್ ಜಿಪಿಎಸ್ ಸಕ್ರಿಯವಾಗಿದೆ • Live GPS continues while in Google Maps',
                  style: TextStyle(
                    color: Color(0xFFA7F3D0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SegmentedButton<GoogleMapsTravelMode>(
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                ),
                segments: const [
                  ButtonSegment(
                    value: GoogleMapsTravelMode.twoWheeler,
                    icon: Icon(Icons.two_wheeler_rounded, size: 16),
                    label: Text('2W', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: GoogleMapsTravelMode.driving,
                    icon: Icon(Icons.directions_car_rounded, size: 16),
                    label: Text('4W', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {_selectedMode},
                onSelectionChanged: (selection) {
                  setState(() => _selectedMode = selection.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isLaunching ? null : _handleLaunchGoogleMaps,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _isLaunching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.navigation_rounded, size: 22),
            label: const Text(
              'ಗೂಗಲ್ ಮ್ಯಾಪ್ಸ್ನಲ್ಲಿ ನ್ಯಾವಿಗೇಟ್ ಮಾಡಿ • Navigate in Google Maps',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
