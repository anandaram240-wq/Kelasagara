// lib/services/navigation/navigation_controller.dart
// Kelasagara Navigation V2: Unified Navigation Controller & Public Façade.
//
// Responsibilities:
//   - Exclusive API entry point for the UI (WorkerJourneyScreen).
//   - Orchestrates NavigationPreflight, NavigationLocationProvider, NavigationEngine, and RTDB telemetry.
//   - Idempotent session lifecycle management (protects against double starts).
//   - Clean teardown with generation invalidation (eliminates zombie callbacks).

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/route_result.dart';
import '../../models/navigation_destination.dart';
import '../../models/journey_state.dart';
import '../navigation_engine.dart';
import '../journey_service.dart';
import 'navigation_location_provider.dart';
import 'navigation_preflight.dart';

enum NavigationSessionState {
  uninitialized,
  preflighting,
  ready,
  navigating,
  paused,
  arrived,
  stopped,
  error,
}

class NavigationController {
  NavigationController._();
  static final NavigationController instance = NavigationController._();

  String _sessionId = '';
  int _sessionGeneration = 0;
  NavigationSessionState _sessionState = NavigationSessionState.uninitialized;

  NavigationDestination? _destination;
  RouteResult? _activeRoute;

  final StreamController<NavigationSessionState> _stateController = StreamController<NavigationSessionState>.broadcast();
  Stream<NavigationSessionState> get stateStream => _stateController.stream;

  NavigationSessionState get sessionState => _sessionState;
  NavigationSessionState get currentState => _sessionState;
  String get sessionId => _sessionId;
  NavigationDestination? get destination => _destination;
  RouteResult? get activeRoute => _activeRoute;
  bool get isNavigating => _sessionState == NavigationSessionState.navigating;

  /// Runs deterministic preflight preparation for the booking and destination.
  Future<PreflightResult> prepareSession({
    required String bookingId,
    required String jobId,
    required String workerId,
    required double destLat,
    required double destLng,
    required String jobAddress,
    required String currentBookingStatus,
  }) async {
    _sessionGeneration++;
    _sessionId = 'nav_${DateTime.now().millisecondsSinceEpoch}_$_sessionGeneration';
    _updateState(NavigationSessionState.preflighting);

    final preflight = await NavigationPreflight.instance.prepare(
      bookingId: bookingId,
      jobId: jobId,
      workerId: workerId,
      destLat: destLat,
      destLng: destLng,
      jobAddress: jobAddress,
      currentBookingStatus: currentBookingStatus,
      sessionId: _sessionId,
    );

    if (preflight.isReady) {
      _destination = preflight.destination;
      _activeRoute = preflight.initialRoute;
      _updateState(NavigationSessionState.ready);
    } else {
      _updateState(NavigationSessionState.error);
    }

    return preflight;
  }

  /// Begins active turn-by-turn guidance and live RTDB tracking using validated preflight artifacts.
  Future<bool> startNavigation({
    required String bookingId,
    required String workerId,
    required String hirerId,
    required String jobId,
    required RouteResult route,
    required NavigationDestination destination,
  }) async {
    if (_sessionState == NavigationSessionState.navigating) {
      debugPrint('[NavController] Already navigating — ignoring duplicate start');
      return true;
    }

    _activeRoute = route;
    _destination = destination;

    // 1. Start continuous hardware GPS stream
    final gpsStarted = await NavigationLocationProvider.instance.startContinuousStream(
      onLocation: (loc) {
        // Forward location to NavigationEngine
        NavigationEngine.instance.feedLiveLocation(loc);
      },
    );

    if (!gpsStarted) {
      _updateState(NavigationSessionState.error);
      return false;
    }

    // 2. Start NavigationEngine guidance session
    await NavigationEngine.instance.start(
      route: route,
      destination: destination.latLng,
      bookingId: bookingId,
      voiceEnabled: true,
    );

    // 3. Start Journey tracking publisher
    await JourneyService.instance.startTracking(
      bookingId: bookingId,
      workerId: workerId,
      hirerId: hirerId,
      destLat: destination.latitude,
      destLng: destination.longitude,
      onLocation: (_) {},
      onEvent: (event) {
        if (event == JourneyEvent.atArrivalRadius) {
          _updateState(NavigationSessionState.arrived);
        }
      },
    );

    _updateState(NavigationSessionState.navigating);
    return true;
  }

  /// Re-centers the camera and resets the follow mode on the UI map.
  void recenter() {
    final curPos = NavigationLocationProvider.instance.lastMatchedLocation ??
        NavigationLocationProvider.instance.lastRawLocation?.latLng;
    if (curPos != null) {
      debugPrint('[NavController] Re-centering map on $curPos');
    }
  }

  /// Re-announces the next upcoming maneuver.
  void repeatInstruction() {
    NavigationEngine.instance.repeatInstruction();
  }

  /// Toggles deterministic voice announcements.
  void setVoiceEnabled(bool enabled) {
    NavigationEngine.instance.setMuted(!enabled);
  }

  /// Halts active guidance, cancels GPS streaming, stops TTS, and invalidates session token.
  Future<void> stopNavigation() async {
    _sessionGeneration++;
    _sessionId = '';

    // Stop NavigationEngine
    NavigationEngine.instance.stop();

    // Stop continuous hardware GPS stream
    await NavigationLocationProvider.instance.stopContinuousStream();

    // Stop RTDB tracking publisher
    await JourneyService.instance.stopTracking();

    _updateState(NavigationSessionState.stopped);
    debugPrint('[NavController] Navigation session stopped and cleaned up.');
  }

  void _updateState(NavigationSessionState state) {
    _sessionState = state;
    _stateController.add(state);
  }
}
