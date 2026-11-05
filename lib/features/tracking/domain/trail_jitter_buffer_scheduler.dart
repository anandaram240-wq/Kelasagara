import 'dart:collection';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'cubic_hermite_spline_interpolator.dart';
import 'hmm_viterbi_shadow_matcher.dart';

class WaypointKeyframe {
  final LatLng position;
  final double bearingDeg;
  final double speedMps;
  final int timestampMs;
  final int durationMs;

  const WaypointKeyframe({
    required this.position,
    required this.bearingDeg,
    required this.speedMps,
    required this.timestampMs,
    required this.durationMs,
  });
}

class SchedulerRenderFrame {
  final LatLng position;
  final double bearingDeg;
  final bool isDeadReckoning;

  const SchedulerRenderFrame({
    required this.position,
    required this.bearingDeg,
    required this.isDeadReckoning,
  });
}

class TrailJitterBufferScheduler {
  final CubicHermiteSplineInterpolator _hermite =
      CubicHermiteSplineInterpolator();
  final Queue<WaypointKeyframe> _queue = Queue<WaypointKeyframe>();

  LatLng? _currentPos;
  double _currentBearing = 0.0;
  double _currentSpeedMps = 0.0;
  int _lastProcessedTrailTs = 0;

  int _segmentStartWallMs = 0;
  int _activeSegmentDurationMs = 1200;
  bool _hasActiveSegment = false;

  bool get isInitialized => _currentPos != null;

  /// Unpacks the incoming RTDB `trail` ring buffer and queues unseen corner vertices
  void enqueueTrailBatch({
    required List<Map<String, dynamic>> rawTrail,
    required LatLng fallbackMatchedPos,
    required double fallbackBearingDeg,
    required double fallbackSpeedMps,
    required int packetTimestampMs,
    required LatLng Function(LatLng pt, double hdg, double spd) roadProjector,
  }) {
    final List<Map<String, dynamic>> unseen = rawTrail
        .where((item) => ((item['ts'] as num?)?.toInt() ?? 0) > _lastProcessedTrailTs)
        .toList();

    if (unseen.isEmpty) {
      _pushKeyframe(
        position: fallbackMatchedPos,
        bearingDeg: fallbackBearingDeg,
        speedMps: fallbackSpeedMps,
        timestampMs: packetTimestampMs,
      );
      return;
    }

    for (final pt in unseen) {
      final int ts = (pt['ts'] as num).toInt();
      final double lat = (pt['lat'] as num).toDouble();
      final double lng = (pt['lng'] as num).toDouble();
      final double hdg = (pt['hdg'] as num).toDouble();
      final double spd = (pt['spd'] as num).toDouble();

      final LatLng snappedPt = roadProjector(LatLng(lat, lng), hdg, spd);
      _pushKeyframe(
        position: snappedPt,
        bearingDeg: hdg,
        speedMps: spd,
        timestampMs: ts,
      );
    }
  }

  void _pushKeyframe({
    required LatLng position,
    required double bearingDeg,
    required double speedMps,
    required int timestampMs,
  }) {
    if (_currentPos == null) {
      _currentPos = position;
      _currentBearing = bearingDeg;
      _currentSpeedMps = speedMps;
      _lastProcessedTrailTs = timestampMs;
      return;
    }

    final int dtMs = (_lastProcessedTrailTs > 0)
        ? (timestampMs - _lastProcessedTrailTs).clamp(350, 1800)
        : 1000;
    _lastProcessedTrailTs = timestampMs;

    _queue.addLast(
      WaypointKeyframe(
        position: position,
        bearingDeg: bearingDeg,
        speedMps: speedMps,
        timestampMs: timestampMs,
        durationMs: dtMs,
      ),
    );

    // Prevent latency buildup if app returns from background: compress queue if > 4 items
    while (_queue.length > 4) {
      _queue.removeFirst();
    }

    if (!_hasActiveSegment) {
      _advanceToNextSegment(DateTime.now().millisecondsSinceEpoch);
    }
  }

  void _advanceToNextSegment(int nowWallMs) {
    if (_queue.isEmpty || _currentPos == null) {
      _hasActiveSegment = false;
      return;
    }

    final WaypointKeyframe next = _queue.removeFirst();
    // Speed up playback slightly (0.88x) when multiple micro-trail points are waiting
    final double queueCompression = _queue.isNotEmpty ? 0.85 : 1.05;
    _activeSegmentDurationMs =
        (next.durationMs * queueCompression).round().clamp(300, 1600);
    _segmentStartWallMs = nowWallMs;
    _hasActiveSegment = true;

    _hermite.setControlSegment(
      startPos: _currentPos!,
      startHeadingDeg: _currentBearing,
      endPos: next.position,
      endHeadingDeg: next.bearingDeg,
    );
    _currentSpeedMps = next.speedMps;
  }

  /// Called at 60fps by Flutter `Ticker`
  SchedulerRenderFrame tickFrame(int nowWallMs) {
    if (_currentPos == null) {
      return const SchedulerRenderFrame(
        position: LatLng(0, 0),
        bearingDeg: 0.0,
        isDeadReckoning: false,
      );
    }

    if (_hasActiveSegment) {
      final int elapsedMs = nowWallMs - _segmentStartWallMs;
      final double t = elapsedMs / _activeSegmentDurationMs;

      if (t < 1.0) {
        final KinematicFrame k = _hermite.sample(t);
        _currentPos = k.position;
        _currentBearing = k.bearingDegrees;
        return SchedulerRenderFrame(
          position: _currentPos!,
          bearingDeg: _currentBearing,
          isDeadReckoning: false,
        );
      } else {
        final KinematicFrame endFrame = _hermite.sample(1.0);
        _currentPos = endFrame.position;
        _currentBearing = endFrame.bearingDegrees;

        if (_queue.isNotEmpty) {
          _advanceToNextSegment(nowWallMs);
          return SchedulerRenderFrame(
            position: _currentPos!,
            bearingDeg: _currentBearing,
            isDeadReckoning: false,
          );
        } else {
          _hasActiveSegment = false;
        }
      }
    }

    // DEAD-RECKONING EXTRAPOLATION (Up to 4.5s during 4G jitter/underpass drops)
    final double coastSec =
        ((nowWallMs - (_segmentStartWallMs + _activeSegmentDurationMs)) / 1000.0)
            .clamp(0.0, 10.0);

    if (coastSec > 0.05 && coastSec <= 4.5 && _currentSpeedMps > 1.2) {
      const double damping = 0.45;
      final double dampedSpeed =
          _currentSpeedMps * math.exp(-damping * coastSec);
      // Step 16ms forward at current damped velocity
      final double stepMeters = dampedSpeed * 0.016;
      _currentPos = HmmViterbiShadowMatcher.offsetPoint(
        _currentPos!,
        stepMeters,
        _currentBearing,
      );
      return SchedulerRenderFrame(
        position: _currentPos!,
        bearingDeg: _currentBearing,
        isDeadReckoning: true,
      );
    }

    return SchedulerRenderFrame(
      position: _currentPos!,
      bearingDeg: _currentBearing,
      isDeadReckoning: false,
    );
  }
}
