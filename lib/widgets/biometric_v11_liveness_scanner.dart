// FILE: lib/widgets/biometric_v11_liveness_scanner.dart

import 'package:flutter/material.dart';
import 'package:kelasagaara/biometrics/biometric_v11_capture_controller.dart';

class BiometricV11LivenessScanner extends StatelessWidget {
  final BiometricV11CaptureController controller;
  final Widget? cameraPreview;
  final VoidCallback? onCancel;

  const BiometricV11LivenessScanner({
    super.key,
    required this.controller,
    this.cameraPreview,
    this.onCancel,
  });

  Color _getFrameColor(V11CaptureState state) {
    switch (state) {
      case V11CaptureState.idle:
      case V11CaptureState.guiding:
        return const Color(0xFFF59E0B); // Amber
      case V11CaptureState.capturing:
      case V11CaptureState.fusing:
      case V11CaptureState.completed:
        return const Color(0xFF10B981); // Emerald Green
      case V11CaptureState.stepUpRequired:
        return const Color(0xFF3B82F6); // Blue
      case V11CaptureState.rejected:
        return const Color(0xFFEF4444); // Red
    }
  }

  IconData _getChallengeIcon(V11ChallengeAction? action) {
    switch (action) {
      case V11ChallengeAction.blink:
        return Icons.visibility_outlined;
      case V11ChallengeAction.turnLeft:
        return Icons.turn_left_rounded;
      case V11ChallengeAction.turnRight:
        return Icons.turn_right_rounded;
      case V11ChallengeAction.nod:
        return Icons.arrow_downward_rounded;
      case null:
        return Icons.face_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final frameColor = _getFrameColor(state);
        final isStepUp = state == V11CaptureState.stepUpRequired;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Background camera preview or fallback background
            if (cameraPreview != null)
              Positioned.fill(child: cameraPreview!)
            else
              Positioned.fill(
                child: Container(color: const Color(0xFF0F172A)),
              ),

            // Oval Guide Overlay
            Center(
              child: Container(
                width: 260,
                height: 350,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.elliptical(130, 175)),
                  border: Border.all(
                    color: frameColor,
                    width: isStepUp ? 4.5 : 3.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: frameColor.withAlpha((0.25 * 255).round()),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),

            // Top Status & Burst Progress Bar
            Positioned(
              top: 48,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withAlpha((0.92 * 255).round()),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: frameColor.withAlpha((0.5 * 255).round())),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isStepUp ? _getChallengeIcon(controller.activeChallenge?.action) : Icons.security,
                          color: frameColor,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            controller.guidanceMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3-Frame Burst Progress Dots
                  if (!isStepUp && state != V11CaptureState.completed)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(BiometricV11CaptureController.requiredFrames, (index) {
                        final isFilled = index < controller.frameCount;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFilled ? const Color(0xFF10B981) : Colors.white24,
                            border: Border.all(
                              color: isFilled ? const Color(0xFF059669) : Colors.white54,
                              width: 1.5,
                            ),
                          ),
                        );
                      }),
                    ),
                ],
              ),
            ),

            // Active Challenge Countdown & Overlay
            if (isStepUp)
              Positioned(
                bottom: 80,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "${controller.challengeSecondsRemaining}s remaining",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Cancel button
            if (onCancel != null)
              Positioned(
                bottom: 24,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  label: const Text(
                    "Cancel Verification",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
