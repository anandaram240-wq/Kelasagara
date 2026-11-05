// lib/services/voice/native_audio_ffi.dart
// Zero-Copy Dart FFI Bridge to Android NDK C++17 Oboe Audio Engine & Hardware VAD

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter/foundation.dart';

typedef _StartNative = ffi.Int32 Function();
typedef _StartDart = int Function();

typedef _StopNative = ffi.Void Function();
typedef _StopDart = void Function();

typedef _GetRmsNative = ffi.Float Function();
typedef _GetRmsDart = double Function();

typedef _PollBargeInNative = ffi.Int32 Function();
typedef _PollBargeInDart = int Function();

typedef _SetSpeakingNative = ffi.Void Function(ffi.Int32 isSpeaking);
typedef _SetSpeakingDart = void Function(int isSpeaking);

typedef _ReadPcmNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Int16> buffer, ffi.Int32 maxSamples);
typedef _ReadPcmDart = int Function(
    ffi.Pointer<ffi.Int16> buffer, int maxSamples);

class NativeOboeAudioBridge {
  static final NativeOboeAudioBridge instance = NativeOboeAudioBridge._();

  bool _isLinked = false;
  bool get isLinked => _isLinked;

  late final _StartDart _start;
  late final _StopDart _stop;
  late final _GetRmsDart _getRms;
  late final _PollBargeInDart _pollBargeIn;
  late final _SetSpeakingDart _setSpeaking;
  late final _ReadPcmDart _readPcm;

  NativeOboeAudioBridge._() {
    if (!Platform.isAndroid) return;
    try {
      final dylib = ffi.DynamicLibrary.open('libkelasagara_audio.so');
      _start = dylib
          .lookupFunction<_StartNative, _StartDart>('kelasagara_audio_start');
      _stop = dylib
          .lookupFunction<_StopNative, _StopDart>('kelasagara_audio_stop');
      _getRms = dylib.lookupFunction<_GetRmsNative, _GetRmsDart>(
          'kelasagara_audio_get_rms');
      _pollBargeIn = dylib
          .lookupFunction<_PollBargeInNative, _PollBargeInDart>(
              'kelasagara_audio_poll_barge_in');
      _setSpeaking = dylib
          .lookupFunction<_SetSpeakingNative, _SetSpeakingDart>(
              'kelasagara_audio_set_assistant_speaking');
      _readPcm = dylib.lookupFunction<_ReadPcmNative, _ReadPcmDart>(
          'kelasagara_audio_read_pcm16');
      _isLinked = true;
    } catch (e) {
      debugPrint('NativeOboeAudioBridge fallback to platform STT: $e');
      _isLinked = false;
    }
  }

  bool startLowLatencyStream() => _isLinked ? _start() == 1 : false;
  void stopLowLatencyStream() {
    if (_isLinked) _stop();
  }

  double readRealtimeRms() => _isLinked ? _getRms() : 0.0;
  bool consumeBargeInTrigger() => _isLinked ? _pollBargeIn() == 1 : false;
  void setAssistantSpeakingState(bool speaking) {
    if (_isLinked) _setSpeaking(speaking ? 1 : 0);
  }

  int readPcm16Samples(ffi.Pointer<ffi.Int16> ptr, int maxSamples) {
    return _isLinked ? _readPcm(ptr, maxSamples) : 0;
  }
}
