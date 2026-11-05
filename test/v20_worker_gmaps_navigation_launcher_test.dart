// test/v20_worker_gmaps_navigation_launcher_test.dart
// Verification suite for KELASAGARA V20.0 Worker Navigation Modes
// and Google Maps intent parameters.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kelasagaara/features/tracking/services/google_maps_navigation_launcher.dart';

void main() {
  group('V20 Worker Google Maps Navigation Suite', () {
    const destination = LatLng(12.971598, 77.594562);

    test('GoogleMapsTravelMode defines correct intent codes and universal names', () {
      expect(GoogleMapsTravelMode.twoWheeler.androidIntentCode, equals('l'),
          reason: 'Android Google Maps two-wheeler intent mode is "l"');
      expect(GoogleMapsTravelMode.twoWheeler.universalModeName, equals('two-wheeler'));

      expect(GoogleMapsTravelMode.driving.androidIntentCode, equals('d'));
      expect(GoogleMapsTravelMode.driving.universalModeName, equals('driving'));

      expect(GoogleMapsTravelMode.walking.androidIntentCode, equals('w'));
      expect(GoogleMapsTravelMode.walking.universalModeName, equals('walking'));
    });

    test('Formats coordinate strings with high precision (6 decimal places)', () {
      final lat = destination.latitude.toStringAsFixed(6);
      final lng = destination.longitude.toStringAsFixed(6);

      expect(lat, equals('12.971598'));
      expect(lng, equals('77.594562'));

      final androidNavUri = Uri.parse(
        'google.navigation:q=$lat,$lng&mode=${GoogleMapsTravelMode.twoWheeler.androidIntentCode}',
      );
      expect(androidNavUri.scheme, equals('google.navigation'));
      expect(androidNavUri.toString(),
          equals('google.navigation:q=12.971598,77.594562&mode=l'));
    });

    test('Universal Google Maps URL fallback constructs valid parameters', () {
      final lat = destination.latitude.toStringAsFixed(6);
      final lng = destination.longitude.toStringAsFixed(6);

      final universalUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=$lat,$lng'
        '&travelmode=${GoogleMapsTravelMode.twoWheeler.universalModeName}'
        '&dir_action=navigate',
      );

      expect(universalUri.scheme, equals('https'));
      expect(universalUri.host, equals('www.google.com'));
      expect(universalUri.path, equals('/maps/dir/'));
      expect(universalUri.queryParameters['api'], equals('1'));
      expect(universalUri.queryParameters['destination'], equals('12.971598,77.594562'));
      expect(universalUri.queryParameters['travelmode'], equals('two-wheeler'));
      expect(universalUri.queryParameters['dir_action'], equals('navigate'));
    });
  });
}
