// lib/services/capture_illumination_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// Service managing application-scoped screen-fill illumination (Phase 3).
/// Controls display brightness during low-light biometric capture without
/// requiring system-level write permissions, and guarantees restoration across
/// all lifecycle exit paths (success, failure, cancellation, pause, disposal).
class CaptureIlluminationService {
  CaptureIlluminationService._();
  static final CaptureIlluminationService instance = CaptureIlluminationService._();

  bool _isIlluminating = false;
  double? _previousBrightness;
  bool _brightnessChanged = false;

  /// Whether adaptive screen-fill illumination is currently active.
  bool get isIlluminating => _isIlluminating;

  /// Enables adaptive screen-fill illumination.
  /// Records the pre-existing application brightness, then elevates application
  /// window brightness to 1.0 (maximum softbox output).
  /// Fails soft on unsupported platforms or platform channel errors.
  Future<bool> enableScreenFill() async {
    if (_isIlluminating) return true;

    try {
      // 1. Record pre-existing application brightness
      try {
        _previousBrightness = await ScreenBrightness.instance.application;
      } catch (e) {
        debugPrint('[CaptureIlluminationService] Warning: Could not read application brightness: $e');
        _previousBrightness = null;
      }

      // 2. Set window-scoped brightness to maximum (1.0)
      await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
      _brightnessChanged = true;
      _isIlluminating = true;
      return true;
    } on PlatformException catch (e) {
      debugPrint('[CaptureIlluminationService] PlatformException on enableScreenFill: ${e.message}');
      _isIlluminating = false;
      return false;
    } catch (e) {
      debugPrint('[CaptureIlluminationService] Unexpected error on enableScreenFill: $e');
      _isIlluminating = false;
      return false;
    }
  }

  /// Disables screen-fill illumination and restores previous brightness.
  /// Guaranteed safe to call redundantly (idempotent).
  Future<void> disableScreenFill() async {
    if (!_isIlluminating && !_brightnessChanged) return;

    try {
      if (_previousBrightness != null && _previousBrightness! >= 0.0 && _previousBrightness! <= 1.0) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(_previousBrightness!);
      } else {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      }
    } catch (e) {
      debugPrint('[CaptureIlluminationService] Warning: Error restoring brightness: $e');
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (_) {}
    } finally {
      _isIlluminating = false;
      _brightnessChanged = false;
      _previousBrightness = null;
    }
  }

  /// Emergency cleanup reset invoked during widget dispose or app lifecycle detachment.
  Future<void> reset() async {
    await disableScreenFill();
  }
}
