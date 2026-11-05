// lib/features/tracking/presentation/widgets/tracking_bottom_sheet.dart
// Production-grade tracking bottom sheet with arrival OTP copy, worker card, and 5-phase stepper.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/tracking_state_model.dart';
import '../../controllers/hirer_tracking_controller.dart';

class TrackingBottomSheet extends StatelessWidget {
  final TrackingStateModel? state;
  final HirerTrackingController? controller;
  final String? workerName;
  final String? workerPhone;
  final VoidCallback? onCallWorker;
  final VoidCallback? onMessageTap;

  const TrackingBottomSheet({
    super.key,
    this.state,
    this.controller,
    this.workerName,
    this.workerPhone,
    this.onCallWorker,
    this.onMessageTap,
  });

  TrackingStateModel get _effectiveState {
    if (state != null) return state!;
    if (controller != null) return controller!.state;
    return const TrackingStateModel(
      workerAnimatedPosition: LatLng(12.9716, 77.5946),
      workerTargetPosition: LatLng(12.9716, 77.5946),
      hirerDestination: LatLng(12.9716, 77.5946),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanPhone.isEmpty) return;
    final Uri url = Uri(scheme: 'tel', path: cleanPhone);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _effectiveState;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            _buildOtpBanner(context, s),
            const SizedBox(height: 16),
            _buildWorkerRow(s),
            const SizedBox(height: 18),
            _buildLifecycleStepper(s),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpBanner(BuildContext context, TrackingStateModel s) {
    final cleanOtp = s.arrivalOtp.trim();
    final List<String> otpDigits = (cleanOtp.isEmpty || cleanOtp == '----' || cleanOtp == '------')
        ? ['-', '-', '-', '-', '-', '-']
        : cleanOtp.split('');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF047857),
            size: 26,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ARRIVAL OTP • ಆಗಮನದ ಕೋಡ್',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF065F46),
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Share with worker at your doorstep to start work',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: s.arrivalOtp));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Arrival OTP copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Row(
              children: otpDigits
                  .map(
                    (d) => Container(
                      margin: const EdgeInsets.only(left: 3),
                      width: otpDigits.length > 4 ? 24 : 30,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF065F46),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        d,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: otpDigits.length > 4 ? 14 : 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerRow(TrackingStateModel s) {
    final effectiveName = (workerName != null && workerName!.isNotEmpty)
        ? workerName!
        : s.workerName;
    final effectivePhone = (workerPhone != null && workerPhone!.isNotEmpty)
        ? workerPhone!
        : s.workerPhone;

    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFE0E7FF),
          child: Text(
            effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'W',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3730A3),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                effectiveName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.workerCategory,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Color(0xFFF59E0B),
                  ),
                  Text(
                    s.workerRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (effectivePhone.isNotEmpty)
          ElevatedButton.icon(
            onPressed: () {
              if (onCallWorker != null) {
                onCallWorker!();
              } else {
                _makePhoneCall(effectivePhone);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF111827),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: const Text(
              'Call',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Widget _buildLifecycleStepper(TrackingStateModel s) {
    const steps = [
      (JourneyLifecyclePhase.accepted, 'Accepted'),
      (JourneyLifecyclePhase.enRoute, 'On Route'),
      (JourneyLifecyclePhase.arrivingSoon, 'Nearby'),
      (JourneyLifecyclePhase.arrivedAtGate, 'Arrived'),
      (JourneyLifecyclePhase.inProgress, 'Started'),
    ];

    final currentIndex = steps.indexWhere((step) => step.$1 == s.phase);

    return Row(
      children: List.generate(steps.length * 2 - 1, (idx) {
        if (idx.isOdd) {
          final stepBefore = idx ~/ 2;
          final isCompleted = stepBefore < currentIndex;
          return Expanded(
            child: Container(
              height: 3,
              color: isCompleted
                  ? const Color(0xFF10B981)
                  : const Color(0xFFE5E7EB),
            ),
          );
        }

        final stepIdx = idx ~/ 2;
        final isDone = stepIdx <= currentIndex;
        final isCurrent = stepIdx == currentIndex;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: isCurrent ? 22 : 16,
              height: isCurrent ? 22 : 16,
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE5E7EB),
                shape: BoxShape.circle,
                border: isCurrent
                    ? Border.all(color: const Color(0xFFA7F3D0), width: 4)
                    : null,
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              steps[stepIdx].$2,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                color: isDone
                    ? const Color(0xFF111827)
                    : const Color(0xFF9CA3AF),
              ),
            ),
          ],
        );
      }),
    );
  }
}
