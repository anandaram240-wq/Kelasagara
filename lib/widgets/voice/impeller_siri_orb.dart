// lib/widgets/voice/impeller_siri_orb.dart
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'siri_fluid_orb.dart'; // Fallback painter while shader warm-loads

export 'siri_fluid_orb.dart' show SiriOrbState, SiriFluidOrb;

class ImpellerSiriOrb extends StatefulWidget {
  final SiriOrbState state;
  final ValueListenable<double> amplitudeListenable;
  final VoidCallback onTap;
  final double size;

  const ImpellerSiriOrb({
    super.key,
    required this.state,
    required this.amplitudeListenable,
    required this.onTap,
    this.size = 180.0,
  });

  @override
  State<ImpellerSiriOrb> createState() => _ImpellerSiriOrbState();
}

class _ImpellerSiriOrbState extends State<ImpellerSiriOrb>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  final ValueNotifier<double> _elapsedSeconds = ValueNotifier<double>(0.0);
  double _smoothedAmp = 0.0;

  @override
  void initState() {
    super.initState();
    _loadAotShader();
    _ticker = createTicker((Duration elapsed) {
      final double raw = widget.amplitudeListenable.value.clamp(0.0, 1.0);
      final double alpha = raw > _smoothedAmp ? 0.42 : 0.16;
      _smoothedAmp = _smoothedAmp + alpha * (raw - _smoothedAmp);
      _elapsedSeconds.value = elapsed.inMicroseconds / 1e6;
    })..start();
  }

  Future<void> _loadAotShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/siri_fluid_orb.frag',
      );
      if (mounted) {
        setState(() {
          _shader = program.fragmentShader();
        });
      }
    } catch (e) {
      debugPrint('Impeller shader asset fallback active: $e');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsedSeconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If shader is not yet compiled into asset bundle, gracefully use CustomPainter
    if (_shader == null) {
      return SiriFluidOrb(
        state: widget.state,
        amplitudeListenable: widget.amplitudeListenable,
        onTap: widget.onTap,
        size: widget.size,
      );
    }

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
          child: CustomPaint(
            painter: _ImpellerOrbShaderPainter(
              shader: _shader!,
              repaint: _elapsedSeconds,
              getTime: () => _elapsedSeconds.value,
              getAmplitude: () => _smoothedAmp,
              stateIndex: widget.state.index.toDouble(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImpellerOrbShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double Function() getTime;
  final double Function() getAmplitude;
  final double stateIndex;

  _ImpellerOrbShaderPainter({
    required this.shader,
    required Listenable repaint,
    required this.getTime,
    required this.getAmplitude,
    required this.stateIndex,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // Only 5 float uniforms updated per frame (< 0.15ms on UI thread)
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, getTime());
    shader.setFloat(3, getAmplitude());
    shader.setFloat(4, stateIndex);

    final Paint paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _ImpellerOrbShaderPainter oldDelegate) {
    return oldDelegate.stateIndex != stateIndex;
  }
}
