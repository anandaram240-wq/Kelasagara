// File: lib/services/play_integrity_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlayIntegrityException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  const PlayIntegrityException(this.code, this.message, [this.details]);

  @override
  String toString() => 'PlayIntegrityException[$code]: $message';
}

class PlayIntegrityService {
  static const MethodChannel _channel = MethodChannel('kelasagara/play_integrity');
  static const int kDefaultCloudProjectNumber = 993968093461; // kelasagara-f127a

  static PlayIntegrityService? _instance;
  static PlayIntegrityService get instance => _instance ??= PlayIntegrityService._();

  PlayIntegrityService._();

  bool _isPrepared = false;
  bool get isPrepared => _isPrepared;

  /**
   * Asynchronously warms up the StandardIntegrityTokenProvider on Android.
   * On non-Android platforms, this is a safe no-op.
   */
  Future<void> prepareIntegrityProvider({int? cloudProjectNumber}) async {
    if (!Platform.isAndroid) return;

    try {
      final success = await _channel.invokeMethod<bool>(
        'prepareIntegrityProvider',
        {'cloudProjectNumber': cloudProjectNumber ?? kDefaultCloudProjectNumber},
      );
      _isPrepared = success ?? false;
      if (kDebugMode) {
        debugPrint('[PlayIntegrityService] Provider prepared: $_isPrepared');
      }
    } on PlatformException catch (e) {
      _isPrepared = false;
      debugPrint('[PlayIntegrityService] Failed to prepare provider: ${e.code} - ${e.message}');
      throw PlayIntegrityException(e.code, e.message ?? 'Unknown provider error', e.details);
    } catch (e) {
      _isPrepared = false;
      throw PlayIntegrityException('INTERNAL_NATIVE_ERROR', e.toString());
    }
  }

  /**
   * Requests an integrity token bound to the provided canonical requestHash.
   */
  Future<String> requestIntegrityToken(String requestHash) async {
    if (!Platform.isAndroid) {
      // Mock/stub for non-Android platforms (iOS / testing)
      return 'mock_integrity_token_non_android';
    }

    try {
      final token = await _channel.invokeMethod<String>(
        'requestIntegrityToken',
        {'requestHash': requestHash},
      );

      if (token == null || token.isEmpty) {
        throw const PlayIntegrityException('INTEGRITY_REQUEST_FAILED', 'Received empty integrity token');
      }

      return token;
    } on PlatformException catch (e) {
      debugPrint('[PlayIntegrityService] Token request failed: ${e.code} - ${e.message}');
      throw PlayIntegrityException(e.code, e.message ?? 'Integrity token error', e.details);
    } catch (e) {
      if (e is PlayIntegrityException) rethrow;
      throw PlayIntegrityException('INTERNAL_NATIVE_ERROR', e.toString());
    }
  }

  /**
   * Forces a refresh and re-preparation of the integrity token provider.
   */
  Future<void> refreshIntegrityProvider({int? cloudProjectNumber}) async {
    if (!Platform.isAndroid) return;

    try {
      final success = await _channel.invokeMethod<bool>(
        'refreshIntegrityProvider',
        {'cloudProjectNumber': cloudProjectNumber ?? kDefaultCloudProjectNumber},
      );
      _isPrepared = success ?? false;
    } on PlatformException catch (e) {
      _isPrepared = false;
      throw PlayIntegrityException(e.code, e.message ?? 'Failed to refresh provider', e.details);
    }
  }

  /**
   * Cleans up native resources.
   */
  Future<void> dispose() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('disposeIntegrityProvider');
      _isPrepared = false;
    } catch (_) {}
  }
}
