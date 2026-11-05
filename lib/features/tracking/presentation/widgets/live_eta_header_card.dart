// lib/features/tracking/presentation/widgets/live_eta_header_card.dart
// Production-grade Live ETA Header Card with signal freshness indicator and Kannada/English labels.

import 'package:flutter/material.dart';
import '../../data/models/tracking_state_model.dart';

class LiveEtaHeaderCard extends StatelessWidget {
  final TrackingStateModel state;
  final VoidCallback onBack;
  final VoidCallback onRecenter;

  const LiveEtaHeaderCard({
    super.key,
    required this.state,
    required this.onBack,
    required this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    final badge = _resolveFreshnessBadge(state.freshness);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: badge.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: badge.color.withValues(alpha: 0.6),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          badge.label,
                          style: TextStyle(
                            color: badge.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (state.isRerouting) ...[
                          const SizedBox(width: 8),
                          const Text(
                            '• Updating route...',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _headlineText(state),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.formattedEta,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      state.formattedDistance,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRecenter,
                tooltip: 'Re-center map',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                ),
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _headlineText(TrackingStateModel s) {
    switch (s.phase) {
      case JourneyLifecyclePhase.accepted:
        return 'ಕೆಲಸಗಾರ ಹೊರಡಲು ಸಿದ್ಧರಾಗಿದ್ದಾರೆ • Preparing';
      case JourneyLifecyclePhase.enRoute:
        return 'ದಾರಿಯಲ್ಲಿದ್ದಾರೆ • On the way to you';
      case JourneyLifecyclePhase.arrivingSoon:
        return 'ಹತ್ತಿರದಲ್ಲಿದ್ದಾರೆ • Arriving at your doorstep';
      case JourneyLifecyclePhase.arrivedAtGate:
        return 'ತಲುಪಿದ್ದಾರೆ • Worker has arrived!';
      case JourneyLifecyclePhase.inProgress:
        return 'ಕೆಲಸ ಪ್ರಗತಿಯಲ್ಲಿದೆ • Work in progress';
    }
  }

  ({String label, Color color}) _resolveFreshnessBadge(
    SignalFreshness freshness,
  ) {
    switch (freshness) {
      case SignalFreshness.live:
        return (label: 'LIVE GPS • ನೇರ ಸಂಪರ್ಕ', color: const Color(0xFF34D399));
      case SignalFreshness.deadReckoning:
        return (
          label: 'SMOOTH TRACK • ಚಲನೆಯಲ್ಲಿದೆ',
          color: const Color(0xFF60A5FA)
        );
      case SignalFreshness.delayed:
        return (
          label: 'SIGNAL DELAYED • ತಡವಾಗುತ್ತಿದೆ',
          color: const Color(0xFFFBBF24)
        );
      case SignalFreshness.weakGps:
        return (
          label: 'WAITING FOR WORKER • ಕಾಯಲಾಗುತ್ತಿದೆ',
          color: const Color(0xFF94A3B8)
        );
    }
  }
}
