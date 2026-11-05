import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local transport connection states for Firebase Realtime Database.
enum LocalConnectionState {
  disconnected,
  connecting,
  connected,
}

/// Remote user presence states.
enum RemotePresenceState {
  unknown,
  online,
  offline,
}

/// Typed representation of a remote user's presence.
class RemotePresence {
  final RemotePresenceState state;
  final DateTime? lastSeen;
  final String? deviceId;

  const RemotePresence({
    required this.state,
    this.lastSeen,
    this.deviceId,
  });

  static const unknown = RemotePresence(state: RemotePresenceState.unknown);
  static const offline = RemotePresence(state: RemotePresenceState.offline);
  static const online = RemotePresence(state: RemotePresenceState.online);

  @override
  String toString() => 'RemotePresence(state: $state, lastSeen: $lastSeen, deviceId: $deviceId)';
}

/// Manages real-time presence using Firebase Realtime Database.
///
/// Features:
/// 1. Decouples local connection state (`/.info/connected`) from remote presence (`presence/{uid}/{deviceId}`).
/// 2. Automatically registers `onDisconnect()` handlers so ungraceful disconnects mark device offline.
/// 3. Streams remote user's presence state across multiple devices.
/// 4. Provides heartbeat & graceful background/foreground transitions.
class PresenceService {
  final FirebaseDatabase? _customDatabase;
  FirebaseDatabase get _rtdb => _customDatabase ?? FirebaseDatabase.instance;

  static final PresenceService instance = PresenceService();

  PresenceService({FirebaseDatabase? database}) : _customDatabase = database;

  StreamSubscription? _infoConnectedSub;
  DatabaseReference? _myPresenceRef;
  String? _myUid;
  String? _deviceId;
  bool _initialized = false;

  final StreamController<LocalConnectionState> _connectionController =
      StreamController<LocalConnectionState>.broadcast();

  LocalConnectionState _localConnection = LocalConnectionState.disconnected;
  LocalConnectionState get localConnection => _localConnection;
  Stream<LocalConnectionState> get connectionStream => _connectionController.stream;

  /// Initialize local device presence for authenticated user [uid].
  Future<void> initialize(String uid) async {
    if (_initialized && _myUid == uid) return;
    _myUid = uid;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      var devId = prefs.getString('kelasagara_device_id');
      if (devId == null) {
        devId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
        await prefs.setString('kelasagara_device_id', devId);
      }
      _deviceId = devId;
    } catch (_) {
      _deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch % 100000}';
    }

    try {
      _myPresenceRef = _rtdb.ref('presence/$uid/$_deviceId');

      // Listen to local connection status via /.info/connected
      _infoConnectedSub?.cancel();
      _infoConnectedSub = _rtdb.ref('.info/connected').onValue.listen((event) async {
        final connected = event.snapshot.value == true;
        if (connected) {
          _localConnection = LocalConnectionState.connected;
          if (!_connectionController.isClosed) {
            _connectionController.add(LocalConnectionState.connected);
          }

          try {
            // Setup onDisconnect handler before setting online state
            await _myPresenceRef?.onDisconnect().set({
              'state': 'offline',
              'lastChanged': ServerValue.timestamp,
              'lastSeen': ServerValue.timestamp,
              'deviceId': _deviceId,
              'appState': 'background',
            });

            // Set online state
            await _myPresenceRef?.set({
              'state': 'online',
              'lastChanged': ServerValue.timestamp,
              'deviceId': _deviceId,
              'appState': 'foreground',
            });
            debugPrint('[PresenceService] Connected and registered online: presence/$uid/$_deviceId');
          } catch (e) {
            debugPrint('[PresenceService] Warning setting presence in RTDB: $e');
          }
        } else {
          _localConnection = LocalConnectionState.disconnected;
          if (!_connectionController.isClosed) {
            _connectionController.add(LocalConnectionState.disconnected);
          }
        }
      }, onError: (e) {
        debugPrint('[PresenceService] .info/connected error: $e');
        _localConnection = LocalConnectionState.disconnected;
        if (!_connectionController.isClosed) {
          _connectionController.add(LocalConnectionState.disconnected);
        }
      });
    } catch (e) {
      debugPrint('[PresenceService] Initialization error: $e');
    }
  }

  /// Mark current device as offline (e.g. app background or logout).
  Future<void> goOffline() async {
    if (_myPresenceRef == null) return;
    try {
      await _myPresenceRef?.set({
        'state': 'offline',
        'lastChanged': ServerValue.timestamp,
        'lastSeen': ServerValue.timestamp,
        'deviceId': _deviceId,
        'appState': 'background',
      });
      debugPrint('[PresenceService] Marked offline: $_myPresenceRef');
    } catch (e) {
      debugPrint('[PresenceService] goOffline error: $e');
    }
  }

  /// Mark current device as online (e.g. app foreground).
  Future<void> goOnline() async {
    if (_myPresenceRef == null) return;
    try {
      await _myPresenceRef?.set({
        'state': 'online',
        'lastChanged': ServerValue.timestamp,
        'deviceId': _deviceId,
        'appState': 'foreground',
      });
      debugPrint('[PresenceService] Marked online: $_myPresenceRef');
    } catch (e) {
      debugPrint('[PresenceService] goOnline error: $e');
    }
  }

  /// Listen to remote user presence for [targetUid].
  /// Emits [RemotePresence] updates.
  Stream<RemotePresence> listenUserPresence(String targetUid) {
    if (targetUid.isEmpty) {
      return Stream.value(RemotePresence.offline);
    }

    try {
      return _rtdb.ref('presence/$targetUid').onValue.map((event) {
        final val = event.snapshot.value;
        if (val == null || val is! Map) {
          return RemotePresence.offline;
        }

        final devices = Map<dynamic, dynamic>.from(val);
        bool anyOnline = false;
        int latestLastSeen = 0;
        String? activeDevice;

        devices.forEach((key, raw) {
          if (raw is Map) {
            final data = Map<dynamic, dynamic>.from(raw);
            final state = data['state']?.toString() ?? 'offline';
            final lastSeen = (data['lastSeen'] as num?)?.toInt() ?? 0;
            final lastChanged = (data['lastChanged'] as num?)?.toInt() ?? 0;

            if (state == 'online') {
              anyOnline = true;
              activeDevice = key.toString();
            }
            if (lastSeen > latestLastSeen) latestLastSeen = lastSeen;
            if (lastChanged > latestLastSeen) latestLastSeen = lastChanged;
          }
        });

        if (anyOnline) {
          return RemotePresence(
            state: RemotePresenceState.online,
            deviceId: activeDevice,
          );
        }

        DateTime? lastSeenDt;
        if (latestLastSeen > 0) {
          lastSeenDt = DateTime.fromMillisecondsSinceEpoch(latestLastSeen);
        }

        return RemotePresence(
          state: RemotePresenceState.offline,
          lastSeen: lastSeenDt,
        );
      }).handleError((e) {
        debugPrint('[PresenceService] Remote presence listen error for $targetUid: $e');
        return RemotePresence.offline;
      });
    } catch (e) {
      debugPrint('[PresenceService] Non-fatal RTDB presence listen note for $targetUid: $e');
      return Stream.value(RemotePresence.offline);
    }
  }

  void dispose() {
    _infoConnectedSub?.cancel();
    _connectionController.close();
  }
}
