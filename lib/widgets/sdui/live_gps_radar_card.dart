// lib/widgets/sdui/live_gps_radar_card.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 2D Kinematic Kalman Filter for dead-reckoning worker GPS coordinates at 120Hz
class WorkerKinematicKalmanFilter {
  // State vector: [px (East m), py (North m), vx (m/s), vy (m/s)]
  double px;
  double py;
  double vx;
  double vy;

  // Simplified diagonal covariance [pVar, vVar] for sub-microsecond 120Hz updates
  double _posVariance = 4.0;
  double _velVariance = 1.5;

  static const double _processNoisePos = 0.08;
  static const double _processNoiseVel = 0.25;
  static const double _gpsMeasurementNoise = 6.25; // ~2.5m GPS std deviation

  WorkerKinematicKalmanFilter({
    required this.px,
    required this.py,
    this.vx = -1.8, // Moving toward hirer at ~6.5 km/h
    this.vy = -1.4,
  });

  /// Called at 120Hz (dt ~ 0.00833s) to advance smooth dead-reckoned position
  void predict(double dt) {
    px += vx * dt;
    py += vy * dt;
    _posVariance += (_velVariance * dt * dt) + _processNoisePos * dt;
    _velVariance += _processNoiseVel * dt;

    // Stop clamping once worker reaches user origin (within 3 meters)
    if (distanceMeters < 3.0) {
      vx *= 0.85;
      vy *= 0.85;
    }
  }

  /// Called when an asynchronous Firebase / WebSocket GPS ping arrives
  void updateMeasurement(double measuredPx, double measuredPy, double dtSinceLastGps) {
    final double kPos = _posVariance / (_posVariance + _gpsMeasurementNoise);
    final double residualX = measuredPx - px;
    final double residualY = measuredPy - py;

    px += kPos * residualX;
    py += kPos * residualY;

    if (dtSinceLastGps > 0.05) {
      final double kVel = _velVariance / (_velVariance + _gpsMeasurementNoise);
      vx += kVel * ((residualX / dtSinceLastGps) - vx) * 0.35;
      vy += kVel * ((residualY / dtSinceLastGps) - vy) * 0.35;
      _velVariance *= (1.0 - kVel * 0.35);
    }

    _posVariance *= (1.0 - kPos);
  }

  double get distanceMeters => math.sqrt(px * px + py * py);
  double get speedMetersPerSec => math.sqrt(vx * vx + vy * vy);
  double get headingRadians => math.atan2(vy, vx);
}

class LiveGpsRadarSduiCard extends StatefulWidget {
  final String workerName;
  final String vehicleBadge;
  final double initialNorthMeters;
  final double initialEastMeters;

  const LiveGpsRadarSduiCard({
    super.key,
    required this.workerName,
    this.vehicleBadge = 'KA-05-EN-4821 • 2-Wheeler',
    this.initialNorthMeters = 210.0,
    this.initialEastMeters = 165.0,
  });

  @override
  State<LiveGpsRadarSduiCard> createState() => _LiveGpsRadarSduiCardState();
}

class _LiveGpsRadarSduiCardState extends State<LiveGpsRadarSduiCard>
    with SingleTickerProviderStateMixin {
  late final WorkerKinematicKalmanFilter _kalman;
  late final Ticker _ticker;
  final ValueNotifier<double> _sweepPhase = ValueNotifier<double>(0.0);
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _kalman = WorkerKinematicKalmanFilter(
      px: widget.initialEastMeters,
      py: widget.initialNorthMeters,
      vx: -3.2,
      vy: -4.1,
    );

    _ticker = createTicker((Duration elapsed) {
      final double dt = _lastTick == Duration.zero
          ? 0.00833
          : (elapsed - _lastTick).inMicroseconds / 1e6;
      _lastTick = elapsed;

      _kalman.predict(dt.clamp(0.0, 0.05));
      _sweepPhase.value = (elapsed.inMicroseconds / 1e6) * 2.2;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sweepPhase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CustomPaint(
                    painter: _KalmanRadarPainter(
                      repaint: _sweepPhase,
                      getPhase: () => _sweepPhase.value,
                      kalman: _kalman,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _sweepPhase,
                    builder: (context, _, __) {
                      final double distM = _kalman.distanceMeters;
                      final double speed = math.max(1.2, _kalman.speedMetersPerSec);
                      final int etaSeconds = (distM / speed).round();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🟢 ಲೈವ್ ಜಿಪಿಎಸ್ ರಾಡಾರ್ (120Hz Kalman)',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.workerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.vehicleBadge,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF065F46),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${distM.toStringAsFixed(0)} m ದೂರ',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ETA: ${etaSeconds}s',
                                style: const TextStyle(
                                  color: Color(0xFFFBBF24),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KalmanRadarPainter extends CustomPainter {
  final double Function() getPhase;
  final WorkerKinematicKalmanFilter kalman;

  _KalmanRadarPainter({
    required Listenable repaint,
    required this.getPhase,
    required this.kalman,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;
    final double phase = getPhase();

    // 1. Radar concentric range rings
    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF10B981).withValues(alpha: 0.25);

    canvas.drawCircle(center, radius, ringPaint);
    canvas.drawCircle(center, radius * 0.65, ringPaint);
    canvas.drawCircle(center, radius * 0.30, ringPaint);

    // 2. Rotating radar sweep cone
    final Paint sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF10B981).withValues(alpha: 0.45),
        ],
        stops: const [0.75, 1.0],
        transform: GradientRotation(phase),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, sweepPaint);

    // 3. Hirer center beacon
    canvas.drawCircle(
      center,
      3.5,
      Paint()..color = const Color(0xFF38BDF8),
    );

    // 4. Kalman-filtered worker position mapped to radar radius (max 300m scale)
    const double maxRangeMeters = 300.0;
    final double normX = (kalman.px / maxRangeMeters).clamp(-0.88, 0.88);
    final double normY = (-kalman.py / maxRangeMeters).clamp(-0.88, 0.88);
    final Offset workerDot = Offset(
      center.dx + normX * radius,
      center.dy + normY * radius,
    );

    canvas.drawCircle(
      workerDot,
      6.5,
      Paint()..color = const Color(0xFFF5820A).withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      workerDot,
      3.8,
      Paint()..color = const Color(0xFFF5820A),
    );
  }

  @override
  bool shouldRepaint(covariant _KalmanRadarPainter oldDelegate) => false;
}
