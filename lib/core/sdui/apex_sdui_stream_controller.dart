// lib/core/sdui/apex_sdui_stream_controller.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../widgets/sdui/live_gps_radar_card.dart';
import 'sdui_components_registry.dart';
import 'zero_copy_binary_sdui.dart';

class ApexSduiStreamController extends ChangeNotifier {
  final List<Uint8List> _binaryCards = [];
  List<Uint8List> get binaryCards => List.unmodifiable(_binaryCards);

  final Set<String> _optimisticBookedIds = {};
  final StreamController<String> _voiceFeedbackChannel =
      StreamController<String>.broadcast();

  /// Stream of synthesized Kannada/Kanglish verbal confirmations triggered by UI actions
  Stream<String> get voiceFeedbackStream => _voiceFeedbackChannel.stream;

  ApexSduiStreamController() {
    registerKelasagaraSduiComponents();
  }

  /// Ingests raw binary SDUI frames from WebSocket with zero JSON parsing overhead
  void ingestBinarySduiFrame(Uint8List rawFrame) {
    _binaryCards.add(rawFrame);
    notifyListeners();
  }

  /// Seeds a complete multi-card voice turn (Booking + Wage Negotiator + Live GPS Radar)
  void seedVoiceTurnCards({
    required String workerId,
    required String workerName,
    required String skillTitle,
    required double distanceKm,
    required int baseWageInr,
  }) {
    _binaryCards
      ..clear()
      ..add(
        SduiBinaryView.encodeFrame(
          cardType: 1, // DirectCanvasBookingCard
          distanceKm: distanceKm,
          rating: 4.9,
          hourlyWageInr: baseWageInr,
          workerNorthMeters: 0,
          workerEastMeters: 0,
          isAvailable: true,
          isFaceRdVerified: true,
          workerId: workerId,
          workerName: workerName,
          skillTitle: skillTitle,
        ),
      )
      ..add(
        SduiBinaryView.encodeFrame(
          cardType: 3, // LiveGpsRadarSduiCard
          distanceKm: distanceKm,
          rating: 4.9,
          hourlyWageInr: baseWageInr,
          workerNorthMeters: 185.0,
          workerEastMeters: 140.0,
          isAvailable: true,
          isFaceRdVerified: true,
          workerId: workerId,
          workerName: workerName,
          skillTitle: skillTitle,
        ),
      );
    notifyListeners();
  }

  Widget buildBinaryCardAt(int index) {
    final SduiBinaryView view = SduiBinaryView(_binaryCards[index]);
    final (String id, String name, String skill) = view.decodeStrings();

    switch (view.cardType) {
      case 1:
        final bool booked = _optimisticBookedIds.contains(id);
        return DirectCanvasBookingCard(
          key: ValueKey<String>('direct_book_$id'),
          workerId: id,
          workerName: name,
          skillSubtitle: skill,
          distanceKm: view.distanceKm,
          rating: view.rating,
          hourlyWageInr: view.hourlyWageInr,
          isBooked: booked,
          onBookTap: () => _handleInstantBook(id, name, view.hourlyWageInr),
        );

      case 3:
        return LiveGpsRadarSduiCard(
          key: ValueKey<String>('kalman_radar_$id'),
          workerName: name,
          initialNorthMeters: view.workerNorthMeters,
          initialEastMeters: view.workerEastMeters,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  void _handleInstantBook(String workerId, String workerName, int wage) {
    // 1. Same-frame optimistic mutation (< 1ms)
    _optimisticBookedIds.add(workerId);
    notifyListeners();

    // 2. Emit bi-directional voice context back to Sarvam AI TTS engine
    _voiceFeedbackChannel.add(
      '$workerName ಅವರನ್ನು ಗಂಟೆಗೆ ₹$wage ದರದಲ್ಲಿ ಬುಕ್ ಮಾಡಲಾಗಿದೆ. ಲೈವ್ ಜಿಪಿಎಸ್ ರಾಡಾರ್ ಸಕ್ರಿಯವಾಗಿದೆ.',
    );
  }

  @override
  void dispose() {
    _voiceFeedbackChannel.close();
    super.dispose();
  }
}
