// lib/services/messaging/messaging_connectivity_service.dart
// Phase 4 & Phase 47: Canonical connection manager decoupling transport and presence.
//
// States:
//   - BOOTSTRAPPING: Initial socket connection in progress (<3s bounded)
//   - ONLINE: Firebase RTDB and Firestore actively connected
//   - DEGRADED: Partial connectivity (e.g. RTDB connected but Firestore stalling)
//   - OFFLINE: Local transport completely disconnected
//   - RECOVERING: Network regained, resynchronizing outbox and presence

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'presence_service.dart';

/// Distinct connection lifecycle states for messaging subsystem.
enum MessagingConnectionStatus {
  bootstrapping,
  online,
  degraded,
  offline,
  recovering,
}

/// Independent four-layer state model (Phase 4).
class MessagingFourLayerState {
  final bool networkAvailable;
  final LocalConnectionState transportState;
  final RemotePresence recipientPresence;
  final MessagingConnectionStatus overallStatus;

  const MessagingFourLayerState({
    required this.networkAvailable,
    required this.transportState,
    required this.recipientPresence,
    required this.overallStatus,
  });

  @override
  String toString() =>
      'FourLayerState(net=$networkAvailable, transport=$transportState, recipient=${recipientPresence.state}, overall=$overallStatus)';
}

/// Central connectivity manager coordinating transport, presence, and outbox recovery.
class MessagingConnectivityService {
  final FirebaseDatabase? _customDatabase;
  FirebaseDatabase get _rtdb => _customDatabase ?? FirebaseDatabase.instance;

  static final MessagingConnectivityService instance = MessagingConnectivityService();

  MessagingConnectivityService({FirebaseDatabase? database}) : _customDatabase = database;

  MessagingConnectionStatus _status = MessagingConnectionStatus.bootstrapping;
  MessagingConnectionStatus get status => _status;

  final StreamController<MessagingConnectionStatus> _statusController =
      StreamController<MessagingConnectionStatus>.broadcast();
  Stream<MessagingConnectionStatus> get statusStream => _statusController.stream;

  StreamSubscription? _rtdbSub;
  Timer? _bootstrapTimer;
  bool _bootstrapCompleted = false;

  /// Start monitoring transport connectivity.
  void initialize() {
    _status = MessagingConnectionStatus.bootstrapping;
    _bootstrapCompleted = false;

    // Bounded 3-second bootstrap timer (Phase 5: no infinite Connecting...)
    _bootstrapTimer?.cancel();
    _bootstrapTimer = Timer(const Duration(seconds: 3), () {
      _bootstrapCompleted = true;
      if (_status == MessagingConnectionStatus.bootstrapping) {
        final currentConn = PresenceService.instance.localConnection;
        _updateStatus(currentConn == LocalConnectionState.connected
            ? MessagingConnectionStatus.online
            : MessagingConnectionStatus.offline);
      }
    });

    try {
      _rtdbSub?.cancel();
      _rtdbSub = _rtdb.ref('.info/connected').onValue.listen((event) {
        final isConnected = event.snapshot.value == true;
        if (isConnected) {
          if (_status == MessagingConnectionStatus.offline) {
            _updateStatus(MessagingConnectionStatus.recovering);
            // Brief grace period for socket handshake before declaring full ONLINE
            Timer(const Duration(milliseconds: 500), () {
              _updateStatus(MessagingConnectionStatus.online);
            });
          } else {
            _updateStatus(MessagingConnectionStatus.online);
          }
        } else {
          if (_bootstrapCompleted) {
            _updateStatus(MessagingConnectionStatus.offline);
          }
        }
      }, onError: (e) {
        debugPrint('[MessagingConnectivityService] RTDB listener note: $e');
        if (_bootstrapCompleted) {
          _updateStatus(MessagingConnectionStatus.offline);
        }
      });
    } catch (e) {
      debugPrint('[MessagingConnectivityService] Non-fatal init note: $e');
      _updateStatus(MessagingConnectionStatus.offline);
    }
  }

  void recordTransportFailure() {
    if (_status == MessagingConnectionStatus.online) {
      _updateStatus(MessagingConnectionStatus.degraded);
    }
  }

  void recordTransportSuccess() {
    if (_status == MessagingConnectionStatus.degraded || _status == MessagingConnectionStatus.recovering) {
      _updateStatus(MessagingConnectionStatus.online);
    }
  }

  void _updateStatus(MessagingConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (!_statusController.isClosed) {
        _statusController.add(newStatus);
      }
      debugPrint('[MessagingConnectivityService] Status transitioned to: $newStatus');
    }
  }

  void dispose() {
    _rtdbSub?.cancel();
    _bootstrapTimer?.cancel();
    _statusController.close();
  }
}
