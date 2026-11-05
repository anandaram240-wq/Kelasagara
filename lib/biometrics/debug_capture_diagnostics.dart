// lib/biometrics/debug_capture_diagnostics.dart
//
// KELASAGARA BIOMATCH V19.6.6
// Safe, Debug-Only Diagnostics & Hardware Telemetry Instrumentation
// Standards: ISO/IEC 19794-5:2025, ISO/IEC 24745:2022, DPDPA 2023

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Diagnostics session snapshot capturing hardware performance metadata
/// without exposing private citizen biometric data, raw pixels, or tokens.
class CaptureDiagnosticsSnapshot {
  final String sessionId;
  final int timestampMs;
  final int cameraInitDurationMs;
  final double streamFpsEstimate;
  final Map<String, dynamic> planeLayout;
  final List<int> cropAndEncodeDurationsMs;
  final List<int> burstFrameIntervalsMs;
  final List<int> jpegByteSizes;
  final int uploadDurationMs;
  final String outcomeStatus;
  final bool isPhotometricActive;

  const CaptureDiagnosticsSnapshot({
    required this.sessionId,
    required this.timestampMs,
    required this.cameraInitDurationMs,
    required this.streamFpsEstimate,
    required this.planeLayout,
    required this.cropAndEncodeDurationsMs,
    required this.burstFrameIntervalsMs,
    required this.jpegByteSizes,
    required this.uploadDurationMs,
    required this.outcomeStatus,
    required this.isPhotometricActive,
  });

  Map<String, dynamic> toSafeJson() {
    final safeFps = (streamFpsEstimate.isNaN || streamFpsEstimate.isInfinite || streamFpsEstimate < 0)
        ? 0.0
        : double.parse(streamFpsEstimate.toStringAsFixed(1));
    return {
      'sessionId': sessionId,
      'timestampMs': timestampMs,
      'cameraInitDurationMs': cameraInitDurationMs >= 0 ? cameraInitDurationMs : 0,
      'streamFpsEstimate': safeFps,
      'planeLayout': planeLayout,
      'cropAndEncodeDurationsMs': cropAndEncodeDurationsMs,
      'burstFrameIntervalsMs': burstFrameIntervalsMs,
      'jpegByteSizes': jpegByteSizes,
      'uploadDurationMs': uploadDurationMs >= 0 ? uploadDurationMs : 0,
      'outcomeStatus': outcomeStatus,
      'isPhotometricActive': isPhotometricActive,
    };
  }
}

/// Safe diagnostics controller active only in debug/profile builds.
/// Guaranteed zero-overhead and no-op in production release mode (kReleaseMode).
class DebugCaptureDiagnostics {
  DebugCaptureDiagnostics._();
  static final DebugCaptureDiagnostics instance = DebugCaptureDiagnostics._();

  @visibleForTesting
  bool? overrideReleaseModeForTesting;

  @visibleForTesting
  void resetForTesting() {
    _currentSessionId = '';
    _sessionStartMs = 0;
    _cameraInitStartMs = 0;
    _cameraInitDurationMs = 0;
    _frameTimestamps.clear();
    _planeLayout = {};
    _cropAndEncodeDurations.clear();
    _burstTimestamps.clear();
    _jpegByteSizes.clear();
    _uploadStartMs = 0;
    _uploadDurationMs = 0;
    _outcomeStatus = 'in_progress';
    _photometricActive = false;
    overrideReleaseModeForTesting = null;
  }

  bool get _isActive {
    if (overrideReleaseModeForTesting != null) {
      return !overrideReleaseModeForTesting!;
    }
    return !kReleaseMode;
  }

  String _currentSessionId = '';
  int _sessionStartMs = 0;
  int _cameraInitStartMs = 0;
  int _cameraInitDurationMs = 0;
  final List<int> _frameTimestamps = [];
  Map<String, dynamic> _planeLayout = {};
  final List<int> _cropAndEncodeDurations = [];
  final List<int> _burstTimestamps = [];
  final List<int> _jpegByteSizes = [];
  int _uploadStartMs = 0;
  int _uploadDurationMs = 0;
  String _outcomeStatus = 'in_progress';
  bool _photometricActive = false;

  /// Begins a new diagnostic capture session.
  void startSession() {
    if (!_isActive) return;
    _currentSessionId = 'diag_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(0xFFFF).toRadixString(16)}';
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    _frameTimestamps.clear();
    _planeLayout.clear();
    _cropAndEncodeDurations.clear();
    _burstTimestamps.clear();
    _jpegByteSizes.clear();
    _cameraInitDurationMs = 0;
    _uploadDurationMs = 0;
    _outcomeStatus = 'in_progress';
    _photometricActive = false;
  }

  void markCameraInitStart() {
    if (!_isActive) return;
    _cameraInitStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  void markCameraInitEnd() {
    if (!_isActive) return;
    if (_cameraInitStartMs > 0) {
      _cameraInitDurationMs = DateTime.now().millisecondsSinceEpoch - _cameraInitStartMs;
    }
  }

  void recordFrameReceived() {
    if (!_isActive) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _frameTimestamps.add(now);
    if (_frameTimestamps.length > 30) {
      _frameTimestamps.removeAt(0);
    }
  }

  void recordPlaneMetadata({
    required int planeCount,
    required List<int> rowStrides,
    required List<int?> pixelStrides,
    required int width,
    required int height,
  }) {
    if (!_isActive) return;
    _planeLayout = {
      'planeCount': planeCount,
      'width': width,
      'height': height,
      'rowStrides': rowStrides,
      'pixelStrides': pixelStrides.map((p) => p ?? 0).toList(),
    };
  }

  void recordCropAndEncodeDuration(int durationMs, int byteSize) {
    if (!_isActive) return;
    _cropAndEncodeDurations.add(durationMs);
    _jpegByteSizes.add(byteSize);
  }

  void recordBurstTimestamps(List<int> timestampsMs) {
    if (!_isActive) return;
    _burstTimestamps.clear();
    _burstTimestamps.addAll(timestampsMs);
  }

  void markUploadStart() {
    if (!_isActive) return;
    _uploadStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  void markUploadEnd(String status) {
    if (!_isActive) return;
    if (_uploadStartMs > 0) {
      _uploadDurationMs = DateTime.now().millisecondsSinceEpoch - _uploadStartMs;
    }
    _outcomeStatus = status;
  }

  void setPhotometricState(bool active) {
    if (!_isActive) return;
    _photometricActive = active;
  }

  /// Exports sanitized telemetry snapshot. Zero private biometric identifiers.
  CaptureDiagnosticsSnapshot exportSnapshot() {
    double fps = 0.0;
    if (_frameTimestamps.length >= 2) {
      final span = _frameTimestamps.last - _frameTimestamps.first;
      if (span > 0) {
        fps = ((_frameTimestamps.length - 1) * 1000.0) / span;
      }
    }

    final intervals = <int>[];
    for (int i = 1; i < _burstTimestamps.length; i++) {
      intervals.add(_burstTimestamps[i] - _burstTimestamps[i - 1]);
    }

    return CaptureDiagnosticsSnapshot(
      sessionId: _currentSessionId.isNotEmpty ? _currentSessionId : 'untracked',
      timestampMs: _sessionStartMs > 0 ? _sessionStartMs : DateTime.now().millisecondsSinceEpoch,
      cameraInitDurationMs: _cameraInitDurationMs,
      streamFpsEstimate: fps,
      planeLayout: Map.unmodifiable(_planeLayout),
      cropAndEncodeDurationsMs: List.unmodifiable(_cropAndEncodeDurations),
      burstFrameIntervalsMs: List.unmodifiable(intervals),
      jpegByteSizes: List.unmodifiable(_jpegByteSizes),
      uploadDurationMs: _uploadDurationMs,
      outcomeStatus: _outcomeStatus,
      isPhotometricActive: _photometricActive,
    );
  }
}
