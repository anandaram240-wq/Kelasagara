// lib/core/performance/frame_budget_isolate_engine.dart
// 120 FPS Frame-Budget Scheduler & Background Geospatial Worker Isolate

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../../services/voice/voice_tool_registry.dart';

class SpeculativeSearchResult {
  final String detectedSkill;
  final double radiusKm;
  final List<WorkerCandidate> rankedCandidates;

  const SpeculativeSearchResult({
    required this.detectedSkill,
    required this.radiusKm,
    required this.rankedCandidates,
  });
}

/// Real-time 120Hz (8.33ms budget) Frame Timing Monitor
class FrameBudgetGuardian {
  static final FrameBudgetGuardian instance = FrameBudgetGuardian._();
  FrameBudgetGuardian._();

  // Notifies widgets if GPU raster times exceed 8.33ms so heavy effects can step down
  final ValueNotifier<bool> highPerformanceTierActive =
      ValueNotifier<bool>(true);

  int _consecutiveOverBudgetFrames = 0;
  bool _attached = false;

  void attachToScheduler() {
    if (_attached) return;
    try {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
      _attached = true;
    } catch (e) {
      debugPrint('[FrameBudgetGuardian] Could not attach to scheduler: $e');
    }
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final FrameTiming timing in timings) {
      final double buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      final double rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;

      // 120 FPS requires both UI and Raster threads to stay under 8.33ms
      if (buildMs > 8.33 || rasterMs > 8.33) {
        _consecutiveOverBudgetFrames++;
        if (_consecutiveOverBudgetFrames > 8 &&
            highPerformanceTierActive.value) {
          highPerformanceTierActive.value = false;
        }
      } else {
        _consecutiveOverBudgetFrames = 0;
        if (!highPerformanceTierActive.value) {
          highPerformanceTierActive.value = true;
        }
      }
    }
  }
}

/// Offloads Kannada/Kanglish NLP & Haversine Geospatial Ranking off the UI thread
class BackgroundWorkerIsolate {
  static final BackgroundWorkerIsolate instance = BackgroundWorkerIsolate._();
  BackgroundWorkerIsolate._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> ensureInitialized() async {
    _initialized = true;
  }

  Future<SpeculativeSearchResult> speculativeParseAndMatch({
    required String utterance,
    required double userLat,
    required double userLng,
  }) async {
    // Executes 100% off the main UI thread so 120 FPS animations never drop a frame
    return Isolate.run(() {
      return _executeGeospatialDialectPipeline(utterance, userLat, userLng);
    });
  }

  static SpeculativeSearchResult _executeGeospatialDialectPipeline(
    String rawText,
    double userLat,
    double userLng,
  ) {
    String norm = rawText.toLowerCase().trim();

    // Dialect & phonetic normalization (Bengaluru, Hubballi-Dharwad, Mangaluru/Tulu-belt Kannada)
    if (norm.contains('ಪ್ಲಂಬರ್') ||
        norm.contains('ನಳ') ||
        norm.contains('ಪೈಪ್') ||
        norm.contains('plumb')) {
      norm = '$norm plumber';
    } else if (norm.contains('ಪೇಂಟರ್') ||
        norm.contains('ಬಣ್ಣ') ||
        norm.contains('paint')) {
      norm = '$norm painter';
    } else if (norm.contains('ಎಲೆಕ್ಟ್ರಿಷಿಯನ್') ||
        norm.contains('ಕರಂಟ್') ||
        norm.contains('ಲೈಟ್') ||
        norm.contains('electr')) {
      norm = '$norm electrician';
    }

    String skill = 'plumber';
    for (final candidateSkill in ['plumber', 'painter', 'electrician']) {
      if (norm.contains(candidateSkill)) {
        skill = candidateSkill;
        break;
      }
    }

    double radiusKm = 5.0;
    final RegExp rRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:km|ಕಿ\.?ಮೀ)');
    final Match? match = rRegex.firstMatch(norm);
    if (match != null) {
      radiusKm = double.tryParse(match.group(1)!) ?? 5.0;
    }

    // Simulated geo-indexed worker pool around Bengaluru coordinates
    final List<({
      String id,
      String name,
      String knSkill,
      String enSkill,
      double lat,
      double lng,
      double rating,
      int jobs,
      int rate,
      String initials
    })> pool = [
      (
        id: 'WKR-KA-901',
        name: 'ಮಂಜುನಾಥ್ ಆರ್. (Manjunath R.)',
        knSkill: skill == 'painter' ? 'ಪೇಂಟರ್' : (skill == 'electrician' ? 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್' : 'ಪ್ಲಂಬರ್'),
        enSkill: skill == 'painter' ? 'Master Painter' : (skill == 'electrician' ? 'Licensed Electrician' : 'Master Plumber'),
        lat: 12.9784,
        lng: 77.6010,
        rating: 4.9,
        jobs: 164,
        rate: 350,
        initials: 'MR',
      ),
      (
        id: 'WKR-KA-902',
        name: 'ಬಸವರಾಜ್ ಪಾಟೀಲ್ (Basavaraj P.)',
        knSkill: skill == 'painter' ? 'ಪೇಂಟರ್' : (skill == 'electrician' ? 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್' : 'ಪ್ಲಂಬರ್'),
        enSkill: skill == 'painter' ? 'Interior Painter' : (skill == 'electrician' ? 'Wiring Specialist' : 'Sanitary Specialist'),
        lat: 12.9610,
        lng: 77.5840,
        rating: 4.8,
        jobs: 119,
        rate: 320,
        initials: 'BP',
      ),
      (
        id: 'WKR-KA-903',
        name: 'ಪ್ರವೀಣ್ ಶೆಟ್ಟಿ (Praveen Shetty)',
        knSkill: skill == 'painter' ? 'ಪೇಂಟರ್' : (skill == 'electrician' ? 'ಎಲೆಕ್ಟ್ರಿಷಿಯನ್' : 'ಪ್ಲಂಬರ್'),
        enSkill: skill == 'painter' ? 'Exterior Painter' : (skill == 'electrician' ? 'Appliance Fixer' : 'Rapid Leak Fixer'),
        lat: 12.9520,
        lng: 77.6120,
        rating: 4.7,
        jobs: 88,
        rate: 300,
        initials: 'PS',
      ),
    ];

    final List<WorkerCandidate> results = pool.map((w) {
      final double dist = _haversineKm(userLat, userLng, w.lat, w.lng);
      return WorkerCandidate(
        workerId: w.id,
        name: w.name,
        skill: w.knSkill,
        distanceMeters: dist * 1000.0,
        distanceDisplay: '${dist.toStringAsFixed(1)} km',
        latitude: w.lat,
        longitude: w.lng,
        isAvailable: true,
        verificationLevel: 'L0_AADHAAR_VERIFIED',
        completedJobs: w.jobs,
        rating: w.rating,
        rankingScore: (w.rating * 20.0) - dist,
        selectionReason: 'Closest top-rated verified ${w.knSkill} (${dist.toStringAsFixed(1)} km)',
      );
    }).toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return SpeculativeSearchResult(
      detectedSkill: skill,
      radiusKm: radiusKm,
      rankedCandidates: results,
    );
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}
