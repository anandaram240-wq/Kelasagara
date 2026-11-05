// lib/services/navigation/map_tile_configuration.dart
// ============================================================================
// KELASAGARA — Canonical Map Tile Configuration & Validation Engine
//
// Responsibilities:
//   - Supports CARTO Basemaps (production raster tiles) and Mapbox (vector/raster).
//   - Hard validation of CARTO_API_KEY and MAPBOX_ACCESS_TOKEN.
//   - Rejects missing, empty, blank whitespace, or placeholder keys at startup.
//   - Constructs valid tile URLs with exactly one key parameter.
//   - Protects against "API KEY REQUIRED" watermark on real devices.
//   - Security: Secrets are NEVER printed to logs.
//   - Android mobile app restriction identity:
//       Package Name: com.kelasagaara.kelasagaara
// ============================================================================

import 'package:flutter/foundation.dart';
import '../../models/navigation_health.dart';

enum MapTileProvider {
  carto,
  mapbox,
  osm,
  unconfigured,
}

class MapTileValidationResult {
  final bool isValid;
  final MapTileProvider provider;
  final String? errorMessage;
  final String? urlTemplate;
  final List<String> subdomains;
  final String attribution;

  const MapTileValidationResult({
    required this.isValid,
    required this.provider,
    this.errorMessage,
    this.urlTemplate,
    this.subdomains = const [],
    this.attribution = '',
  });

  factory MapTileValidationResult.valid({
    required MapTileProvider provider,
    required String urlTemplate,
    List<String> subdomains = const [],
    String attribution = '',
  }) {
    return MapTileValidationResult(
      isValid: true,
      provider: provider,
      urlTemplate: urlTemplate,
      subdomains: subdomains,
      attribution: attribution,
    );
  }

  factory MapTileValidationResult.invalid({
    required MapTileProvider provider,
    required String errorMessage,
  }) {
    return MapTileValidationResult(
      isValid: false,
      provider: provider,
      errorMessage: errorMessage,
    );
  }
}

class MapTileConfiguration {
  MapTileConfiguration._();
  static final MapTileConfiguration instance = MapTileConfiguration._();

  static const String _cartoKeyEnv =
      String.fromEnvironment('CARTO_API_KEY', defaultValue: '');
  static const String _mapboxTokenEnv =
      String.fromEnvironment('MAPBOX_ACCESS_TOKEN', defaultValue: '');

  /// OpenStreetMap standard tile server URL template
  static const String osmTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Standard OpenStreetMap legal attribution
  static const String osmAttribution =
      '© OpenStreetMap contributors';

  /// Default subdomains for CARTO CDN
  static const List<String> cartoSubdomains = ['a', 'b', 'c', 'd'];

  /// Validates a candidate CARTO API key.
  static bool isValidCartoKey(String? key) {
    if (key == null) return false;
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    // Reject common template placeholders
    final lower = trimmed.toLowerCase();
    if (lower == 'your_key' ||
        lower == 'your_carto_key' ||
        lower == 'carto_api_key' ||
        lower == '<build_time_key>' ||
        lower == '<redacted>' ||
        lower == 'placeholder') {
      return false;
    }
    // CARTO keys are alphanumeric tokens
    return trimmed.length >= 10;
  }

  /// Validates a candidate Mapbox access token.
  static bool isValidMapboxToken(String? token) {
    if (token == null) return false;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('your_') ||
        lower == '<build_time_key>' ||
        lower == '<redacted>') {
      return false;
    }
    return trimmed.startsWith('pk.') && trimmed.length > 20;
  }

  /// Builds a sanitized CARTO Voyager tile URL template with the API key.
  /// Guarantees exactly one `?key=` parameter without duplication or double query signs.
  static String buildCartoUrlTemplate(String key) {
    final cleanKey = key.trim();
    return 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png?key=$cleanKey';
  }

  /// Builds a Mapbox tile URL template.
  static String buildMapboxUrlTemplate(String token, {bool nightMode = true}) {
    final cleanToken = token.trim();
    final style = nightMode ? 'navigation-night-v1' : 'streets-v12';
    return 'https://api.mapbox.com/styles/v1/mapbox/$style/tiles/256/{z}/{x}/{y}@2x?access_token=$cleanToken';
  }

  /// Evaluates and validates the active build-time map configuration.
  /// Priority:
  ///   1. Mapbox if valid MAPBOX_ACCESS_TOKEN provided
  ///   2. CARTO if valid CARTO_API_KEY provided
  ///   3. OpenStreetMap standard tiles if [allowOsmFallback] is true (Case B2: demo/evaluation)
  MapTileValidationResult validateConfiguration({
    String? explicitCartoKey,
    String? explicitMapboxToken,
    bool allowOsmFallback = true,
  }) {
    final mapboxToken = explicitMapboxToken ?? _mapboxTokenEnv;
    final cartoKey = explicitCartoKey ?? _cartoKeyEnv;

    // 1. Check Mapbox if token provided
    if (mapboxToken.isNotEmpty) {
      if (isValidMapboxToken(mapboxToken)) {
        debugPrint('[MAP_CONFIG] provider=MAPBOX configured=true');
        return MapTileValidationResult.valid(
          provider: MapTileProvider.mapbox,
          urlTemplate: buildMapboxUrlTemplate(mapboxToken),
          attribution: '© Mapbox',
        );
      } else {
        debugPrint('[MAP_CONFIG] provider=MAPBOX configured=false reason=invalid_token');
      }
    }

    // 2. Check CARTO
    if (cartoKey.isNotEmpty) {
      if (isValidCartoKey(cartoKey)) {
        debugPrint('[MAP_CONFIG] provider=CARTO configured=true');
        return MapTileValidationResult.valid(
          provider: MapTileProvider.carto,
          urlTemplate: buildCartoUrlTemplate(cartoKey),
          subdomains: cartoSubdomains,
          attribution: '© CARTO',
        );
      } else if (!allowOsmFallback) {
        debugPrint('[MAP_CONFIG] provider=CARTO configured=false reason=invalid_api_key');
        return MapTileValidationResult.invalid(
          provider: MapTileProvider.carto,
          errorMessage: 'CARTO API key is malformed or placeholder.',
        );
      } else {
        debugPrint('[MAP_CONFIG] provider=CARTO configured=false reason=invalid_api_key -> falling back to OSM');
      }
    }

    // 3. Fallback to OpenStreetMap (Case B2: No real CARTO/Mapbox credentials)
    if (allowOsmFallback) {
      debugPrint('[MAP_CONFIG] provider=OSM configured=true (fallback/demo)');
      return MapTileValidationResult.valid(
        provider: MapTileProvider.osm,
        urlTemplate: osmTileUrlTemplate,
        subdomains: const [],
        attribution: osmAttribution,
      );
    }

    // 4. Strict unconfigured mode
    debugPrint('[MAP_CONFIG] provider=CARTO configured=false reason=missing_api_key');
    return MapTileValidationResult.invalid(
      provider: MapTileProvider.unconfigured,
      errorMessage: 'Map service configuration missing: CARTO_API_KEY required.',
    );
  }

  /// Maps the validation result to the enterprise MapStatus.
  MapStatus getMapStatus({bool allowOsmFallback = true}) {
    final res = validateConfiguration(allowOsmFallback: allowOsmFallback);
    return res.isValid ? MapStatus.ready : MapStatus.configurationError;
  }
}
