// test/v20_map_tile_configuration_test.dart
// Verification suite for KELASAGARA V20.0 Map Tile Provider,
// OSM fallback, and CARTO watermark elimination.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/navigation/map_tile_configuration.dart';

void main() {
  group('V20 Map Tile Provider & Watermark Elimination Suite', () {
    test('Default configuration safely falls back to OpenStreetMap standard tiles without watermarks', () {
      final config = MapTileConfiguration.instance.validateConfiguration();

      expect(config.isValid, isTrue);
      expect(config.provider, equals(MapTileProvider.osm));
      expect(config.urlTemplate, equals(MapTileConfiguration.osmTileUrlTemplate));
      expect(config.urlTemplate, contains('tile.openstreetmap.org'));
      expect(config.urlTemplate, isNot(contains('cartocdn.com')));
      expect(config.subdomains, isEmpty);
      expect(config.attribution, contains('OpenStreetMap'));
    });

    test('Rejects placeholder CARTO keys and falls back to OSM', () {
      final placeholders = [
        'your_key',
        'your_carto_key',
        'carto_api_key',
        '<build_time_key>',
        '<redacted>',
        'placeholder',
        '   ',
        '',
        'short',
      ];

      for (final ph in placeholders) {
        expect(MapTileConfiguration.isValidCartoKey(ph), isFalse,
            reason: 'Should reject placeholder: "$ph"');

        final res = MapTileConfiguration.instance.validateConfiguration(
          explicitCartoKey: ph,
          allowOsmFallback: true,
        );
        expect(res.isValid, isTrue);
        expect(res.provider, equals(MapTileProvider.osm));
      }
    });

    test('Rejects missing CARTO key when OSM fallback is disallowed', () {
      final res = MapTileConfiguration.instance.validateConfiguration(
        explicitCartoKey: '',
        explicitMapboxToken: '',
        allowOsmFallback: false,
      );

      expect(res.isValid, isFalse);
      expect(res.provider, equals(MapTileProvider.unconfigured));
      expect(res.errorMessage, contains('CARTO_API_KEY required'));
    });

    test('Constructs valid CARTO Voyager URL with single ?key= parameter when genuine key provided', () {
      const genuineKey = 'a1b2c3d4e5f6g7h8i9j0';
      expect(MapTileConfiguration.isValidCartoKey(genuineKey), isTrue);

      final url = MapTileConfiguration.buildCartoUrlTemplate(genuineKey);
      expect(url, contains('basemaps.cartocdn.com/rastertiles/voyager'));
      expect(url, endsWith('?key=$genuineKey'));
      expect('?'.allMatches(url).length, equals(1));
    });
  });
}
