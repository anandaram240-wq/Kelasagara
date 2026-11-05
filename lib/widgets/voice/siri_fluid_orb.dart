// lib/widgets/voice/siri_fluid_orb.dart
// Siri Fluid Orb — Multi-layer organic wave physics Canvas fallback painter

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum SiriOrbState {
  idle,
  listening,
  thinking,
  speaking,
}

class SiriFluidOrb extends StatefulWidget {
  final SiriOrbState state;
  final ValueListenable<double> amplitudeListenable;
  final VoidCallback onTap;
  final double size;

  const SiriFluidOrb({
    super.key,
    required this.state,
    required this.amplitudeListenable,
    required this.onTap,
    this.size = 180.0,
  });

  @override
  State<SiriFluidOrb> createState() => _SiriFluidOrbState();
}

class _SiriFluidOrbState extends State<SiriFluidOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;
  double _smoothedAmp = 0.0;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    widget.amplitudeListenable.addListener(_onAmpChanged);
  }

  void _onAmpChanged() {
    final raw = widget.amplitudeListenable.value.clamp(0.0, 1.0);
    final alpha = raw > _smoothedAmp ? 0.42 : 0.16;
    _smoothedAmp = _smoothedAmp + alpha * (raw - _smoothedAmp);
  }

  @override
  void dispose() {
    widget.amplitudeListenable.removeListener(_onAmpChanged);
    _waveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _waveCtrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _SiriFluidOrbPainter(
                  state: widget.state,
                  progress: _waveCtrl.value,
                  amplitude: _smoothedAmp,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SiriFluidOrbPainter extends CustomPainter {
  final SiriOrbState state;
  final double progress;
  final double amplitude;

  _SiriFluidOrbPainter({
    required this.state,
    required this.progress,
    required this.amplitude,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = (size.width / 2) * 0.58;
    final time = progress * 2.0 * math.pi;

    // Palette resolution
    final (Color colA, Color colB, Color colC) = switch (state) {
      SiriOrbState.idle => (
          const Color(0xFF7C3AED),
          const Color(0xFFF5820A),
          const Color(0xFFC084FC)
        ),
      SiriOrbState.listening => (
          const Color(0xFF2563EB),
          const Color(0xFF06B6D4),
          const Color(0xFF38BDF8)
        ),
      SiriOrbState.thinking => (
          const Color(0xFF4C1D95),
          const Color(0xFFF59E0B),
          const Color(0xFFA855F7)
        ),
      SiriOrbState.speaking => (
          const Color(0xFF059669),
          const Color(0xFF10B981),
          const Color(0xFF34D399)
        ),
    };

    // Layer 1: Ambient Outer Glow / Bloom
    final dynamicAmp = 0.04 + (amplitude * 0.22);
    final glowRadius = baseRadius * (1.18 + dynamicAmp);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          colA.withValues(alpha: 0.45 + (amplitude * 0.3)),
          colB.withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    canvas.drawCircle(center, glowRadius, glowPaint);

    // Layer 2: Deformed Harmonic Wave 1
    final path1 = Path();
    const int segments = 48;
    for (int i = 0; i < segments; i++) {
      final theta = (i / segments) * 2.0 * math.pi;
      final wave = math.sin(theta * 3.0 + time * 1.5) *
          math.cos(theta * 2.0 - time) *
          dynamicAmp;
      final r = baseRadius * (1.0 + wave);
      final x = center.dx + r * math.cos(theta);
      final y = center.dy + r * math.sin(theta);
      if (i == 0) {
        path1.moveTo(x, y);
      } else {
        path1.lineTo(x, y);
      }
    }
    path1.close();

    final paint1 = Paint()
      ..shader = LinearGradient(
        colors: [
          colA.withValues(alpha: 0.8),
          colB.withValues(alpha: 0.7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius));
    canvas.drawPath(path1, paint1);

    // Layer 3: High-frequency inner fluid wave
    final path2 = Path();
    for (int i = 0; i < segments; i++) {
      final theta = (i / segments) * 2.0 * math.pi;
      final wave = math.sin(theta * 4.0 - time * 2.0) * (dynamicAmp * 0.75);
      final r = baseRadius * (0.85 + wave);
      final x = center.dx + r * math.cos(theta);
      final y = center.dy + r * math.sin(theta);
      if (i == 0) {
        path2.moveTo(x, y);
      } else {
        path2.lineTo(x, y);
      }
    }
    path2.close();

    final paint2 = Paint()
      ..shader = LinearGradient(
        colors: [
          colB.withValues(alpha: 0.85),
          colC.withValues(alpha: 0.9),
        ],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 0.85));
    canvas.drawPath(path2, paint2);

    // Layer 4: Specular Glassmorphic Core Highlight
    final specularPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.45,
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 0.7));
    canvas.drawCircle(
      center + const Offset(-6, -6),
      baseRadius * 0.55,
      specularPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SiriFluidOrbPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.state != state;
  }
}
