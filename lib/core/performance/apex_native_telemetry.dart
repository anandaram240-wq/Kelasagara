// lib/core/performance/apex_native_telemetry.dart
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

typedef _StartAudioNative = ffi.Int32 Function();
typedef _StartAudioDart = int Function();

typedef _GetTelemetryPtrNative = ffi.Pointer<ffi.Float> Function();
typedef _GetTelemetryPtrDart = ffi.Pointer<ffi.Float> Function();

typedef _InitAdpfNative = ffi.Void Function(ffi.Int32 tid);
typedef _InitAdpfDart = void Function(int tid);

typedef _ReportFrameNative = ffi.Void Function(ffi.Int64 durationNanos);
typedef _ReportFrameDart = void Function(int durationNanos);

typedef _SetSpeakingNative = ffi.Void Function(ffi.Int32 speaking);
typedef _SetSpeakingDart = void Function(int speaking);

class ApexHardwareBridge {
  static final ApexHardwareBridge instance = ApexHardwareBridge._();

  Float32List _sharedRegisters = Float32List(12);
  bool _isNativeBound = false;

  late final _StartAudioDart _startAudio;
  late final _InitAdpfDart _initAdpf;
  late final _ReportFrameDart _reportFrame;
  late final _SetSpeakingDart _setSpeaking;

  ApexHardwareBridge._() {
    if (!Platform.isAndroid) return;
    try {
      final dylib = ffi.DynamicLibrary.open('libkelasagara_audio.so');
      _startAudio = dylib.lookupFunction<_StartAudioNative, _StartAudioDart>(
          'kelasagara_apex_start_audio');
      final getPtr = dylib
          .lookupFunction<_GetTelemetryPtrNative, _GetTelemetryPtrDart>(
              'kelasagara_apex_get_shared_telemetry_ptr');
      _initAdpf = dylib.lookupFunction<_InitAdpfNative, _InitAdpfDart>(
          'kelasagara_apex_init_adpf_120hz');
      _reportFrame = dylib.lookupFunction<_ReportFrameNative, _ReportFrameDart>(
          'kelasagara_apex_report_frame_nanos');
      _setSpeaking = dylib.lookupFunction<_SetSpeakingNative, _SetSpeakingDart>(
          'kelasagara_apex_set_assistant_speaking');

      // Map the 12 C++ float registers directly into a zero-copy Dart Float32List view
      final ffi.Pointer<ffi.Float> rawPtr = getPtr();
      if (rawPtr.address != 0) {
        _sharedRegisters = rawPtr.asTypedList(12);
        _isNativeBound = true;
      }
    } catch (e) {
      debugPrint('ApexHardwareBridge running in pure-Dart fallback mode: $e');
    }
  }

  void activate120HzAdpfAndAudio() {
    if (_isNativeBound) {
      _initAdpf(0); // Binds calling UI thread to Android ADPF 8.33ms target
      _startAudio();
    }
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimingsReport);
  }

  void _onFrameTimingsReport(List<FrameTiming> timings) {
    if (!_isNativeBound) return;
    for (final FrameTiming t in timings) {
      final int totalNanos =
          (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds) *
              1000;
      _reportFrame(totalNanos);
    }
  }

  /// Zero-copy direct memory reads (< 0.02ms)
  Float32List get registers => _sharedRegisters;
  double get rms => _sharedRegisters[0];
  double get spectralCentroid => _sharedRegisters[1];
  bool get isHumanSpeechActive => _sharedRegisters[2] >= 0.5;

  bool consumeHardwareBargeIn() {
    if (_sharedRegisters[3] >= 0.5) {
      _sharedRegisters[3] = 0.0; // Clear flag directly in shared memory
      return true;
    }
    return false;
  }

  void setAssistantSpeaking(bool speaking) {
    if (_isNativeBound) {
      _setSpeaking(speaking ? 1 : 0);
    } else {
      _sharedRegisters[3] = 0.0;
    }
  }
}
