// lib/services/voice/district_dialect_mapper.dart
// Maps every Karnataka district → its dialect zone.
// Used by VoiceSessionManager to auto-activate the correct Sarvam keyterm set
// and boost dialect-specific recognition accuracy.

import 'regional_kannada_normalizer.dart';

class DistrictDialectMapper {
  /// Returns the dominant dialect profile for a given district name.
  /// Falls back to [RegionalKannadaProfile.standard] for unknown inputs.
  static RegionalKannadaProfile profileForDistrict(String district) {
    return _zoneMap[district] ??
        _zoneMap[_normalize(district)] ??
        RegionalKannadaProfile.standard;
  }

  /// Returns Sarvam ASR keyterms optimised for the given district.
  static List<String> keytermsForDistrict(String district) {
    final profile = profileForDistrict(district);
    return KannadaPhoneticNormalizer.dialectKeytermsPublic(profile);
  }

  static String _normalize(String d) => d.trim().toLowerCase();

  // ── 30 Districts → 8 Zones ─────────────────────────────────────────────────
  static const Map<String, RegionalKannadaProfile> _zoneMap = {
    // ── Zone 1 — Southern Standard ──────────────────────────────────────────
    'Bengaluru Urban':   RegionalKannadaProfile.mysuruBengaluru,
    'Bengaluru Rural':   RegionalKannadaProfile.mysuruBengaluru,
    'Mysuru':            RegionalKannadaProfile.mysuruBengaluru,
    'Mandya':            RegionalKannadaProfile.mysuruBengaluru,
    'Ramanagara':        RegionalKannadaProfile.mysuruBengaluru,
    'Chamarajanagar':    RegionalKannadaProfile.mysuruBengaluru,
    'Kolar':             RegionalKannadaProfile.mysuruBengaluru,
    'Chikkaballapur':    RegionalKannadaProfile.mysuruBengaluru,
    'Tumakuru':          RegionalKannadaProfile.mysuruBengaluru,
    'Chitradurga':       RegionalKannadaProfile.mysuruBengaluru,

    // ── Zone 2 — North Karnataka / Dharwad ──────────────────────────────────
    'Dharwad':           RegionalKannadaProfile.northKarnataka,
    'Haveri':            RegionalKannadaProfile.northKarnataka,
    'Gadag':             RegionalKannadaProfile.northKarnataka,
    'Uttara Kannada':    RegionalKannadaProfile.northKarnataka,
    'Koppal':            RegionalKannadaProfile.northKarnataka,
    'Davanagere':        RegionalKannadaProfile.northKarnataka,

    // ── Zone 3 — Kalyana Karnataka (Urdu/Hindi influenced) ──────────────────
    'Kalaburagi':        RegionalKannadaProfile.kalyanaKarnataka,
    'Bidar':             RegionalKannadaProfile.kalyanaKarnataka,
    'Raichur':           RegionalKannadaProfile.kalyanaKarnataka,
    'Yadgir':            RegionalKannadaProfile.kalyanaKarnataka,
    'Ballari':           RegionalKannadaProfile.kalyanaKarnataka,

    // ── Zone 4 — Coastal / Kundagannada (Tulu influenced) ───────────────────
    'Dakshina Kannada':  RegionalKannadaProfile.coastal,
    'Udupi':             RegionalKannadaProfile.coastal,

    // ── Zone 5 — Malenadu ───────────────────────────────────────────────────
    'Hassan':            RegionalKannadaProfile.malenadu,
    'Chikkamagaluru':    RegionalKannadaProfile.malenadu,
    'Shivamogga':        RegionalKannadaProfile.malenadu,

    // ── Zone 5b — Kodagu ────────────────────────────────────────────────────
    'Kodagu':            RegionalKannadaProfile.kodagu,

    // ── Zone 7 — Belagavi Border (Marathi influenced) ───────────────────────
    'Belagavi':          RegionalKannadaProfile.belagaviBorder,
    'Vijayapura':        RegionalKannadaProfile.belagaviBorder,
    'Bagalkot':          RegionalKannadaProfile.belagaviBorder,
  };

  /// Returns a human-readable description of the dialect zone.
  static String zoneNameFor(String district) {
    switch (profileForDistrict(district)) {
      case RegionalKannadaProfile.mysuruBengaluru:
        return 'Southern Standard Kannada';
      case RegionalKannadaProfile.northKarnataka:
        return 'North Karnataka / Dharwad Kannada';
      case RegionalKannadaProfile.kalyanaKarnataka:
        return 'Kalyana Karnataka (Urdu-influenced)';
      case RegionalKannadaProfile.coastal:
        return 'Coastal / Kundagannada (Tulu-influenced)';
      case RegionalKannadaProfile.malenadu:
        return 'Malenadu / Coffee Belt Kannada';
      case RegionalKannadaProfile.kodagu:
        return 'Kodagu / Coorg Kannada';
      case RegionalKannadaProfile.belagaviBorder:
        return 'Belagavi Border (Marathi-influenced)';
      case RegionalKannadaProfile.havyaka:
        return 'Havyaka / Old Kannada';
      default:
        return 'Standard Kannada';
    }
  }
}

// ── Public extension on KannadaPhoneticNormalizer for keyterms ───────────────
extension DialectKeytermsPublic on KannadaPhoneticNormalizer {
  static List<String> call(RegionalKannadaProfile profile) =>
      KannadaPhoneticNormalizer.dialectKeytermsPublic(profile);
}

extension DialectKeytermsExt on KannadaPhoneticNormalizer {
  static List<String> dialectKeytermsFor(RegionalKannadaProfile profile) =>
      KannadaPhoneticNormalizer.dialectKeytermsPublic(profile);
}
