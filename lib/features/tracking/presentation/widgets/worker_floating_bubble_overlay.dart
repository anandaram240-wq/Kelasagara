// lib/features/tracking/presentation/widgets/worker_floating_bubble_overlay.dart
// Production-grade floating bubble overlay for workers navigating in external Google Maps.
// Provides 1-tap return to Kelasagaara, live geofence status, and instant OTP verification.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../services/enterprise_worker_telemetry_isolate.dart';
import 'worker_otp_verification_sheet.dart';

class WorkerFloatingBubbleOverlay extends StatefulWidget {
  final String bookingId;
  final String workerId;
  final String hirerName;
  final LatLng jobDestination;
  final VoidCallback? onReturnToApp;

  const WorkerFloatingBubbleOverlay({
    super.key,
    required this.bookingId,
    required this.workerId,
    required this.hirerName,
    required this.jobDestination,
    this.onReturnToApp,
  });

  @override
  State<WorkerFloatingBubbleOverlay> createState() =>
      _WorkerFloatingBubbleOverlayState();
}

class _WorkerFloatingBubbleOverlayState
    extends State<WorkerFloatingBubbleOverlay> {
  Offset _bubbleOffset = const Offset(16, 120);
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return Positioned(
      left: _bubbleOffset.dx.clamp(8.0, math.max(8.0, screenSize.width - 280.0)),
      top: _bubbleOffset.dy.clamp(40.0, math.max(40.0, screenSize.height - 180.0)),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _bubbleOffset += details.delta;
          });
        },
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(_isExpanded ? 20 : 30),
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.all(_isExpanded ? 16 : 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(_isExpanded ? 20 : 30),
              border: Border.all(
                color: const Color(0xFF10B981),
                width: 2.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: _isExpanded ? _buildExpandedCard() : _buildCollapsedPill(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedPill() {
    return InkWell(
      onTap: () => setState(() => _isExpanded = true),
      borderRadius: BorderRadius.circular(30),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.two_wheeler_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 8),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Kelasagaara Live',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              Text(
                'ನ್ಯಾವಿಗೇಶನ್ ಸಕ್ರಿಯ • Tap to expand',
                style: TextStyle(
                  color: Color(0xFFA7F3D0),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.expand_more_rounded,
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildExpandedCard() {
    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  const Text(
                    'Kelasagaara Active Job',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _isExpanded = false),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ಗ್ರಾಹಕರು: ${widget.hirerName}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'ಹಿನ್ನೆಲೆ ಲೈವ್ ಜಿಪಿಎಸ್ ಟ್ರ್ಯಾಕಿಂಗ್ ಸಕ್ರಿಯವಾಗಿದೆ (60fps)',
            style: TextStyle(
              color: Color(0xFFA7F3D0),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    WorkerOtpVerificationSheet.show(
                      context,
                      bookingId: widget.bookingId,
                      hirerName: widget.hirerName,
                      onVerified: () async {
                        await EnterpriseWorkerTelemetryService.instance
                            .stopShadowTracking();
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.pin_rounded, size: 16),
                  label: const Text(
                    'OTP ನಮೂದಿಸಿ',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() => _isExpanded = false);
                  widget.onReturnToApp?.call();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'ಆಪ್‌ಗೆ ಮರಳಿ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
