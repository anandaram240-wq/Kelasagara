import 'package:dio/dio.dart';
import '../models/work_location.dart';

/// OpenStreetMap Nominatim geocoding — free, no API key required.
/// Rate limit: 1 req/sec. Debounce calls in the UI layer.
class NominatimService {
  static final _dio = Dio(BaseOptions(
    baseUrl: 'https://nominatim.openstreetmap.org',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'KelasaGaara/17 (anandaananda16919@gmail.com)',
      'Accept-Language': 'en',
    },
  ));

  static Future<List<NominatimResult>> search(String query) async {
    if (query.trim().length < 3) return [];
    try {
      final resp = await _dio.get('/search', queryParameters: {
        'q':              '$query, Karnataka, India',
        'format':         'json',
        'addressdetails': 1,
        'limit':          8,
        'countrycodes':   'in',
      });
      final data = resp.data as List<dynamic>;
      return data.map((e) => NominatimResult.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<WorkLocation?> reverseGeocode(double lat, double lng) async {
    try {
      final resp = await _dio.get('/reverse', queryParameters: {
        'lat':            lat,
        'lon':            lng,
        'format':         'json',
        'addressdetails': 1,
        'zoom':           16,
      });
      if (resp.statusCode != 200 || resp.data == null) return null;
      final data = resp.data as Map<String, dynamic>;
      if (data['error'] != null) return null;
      return _parse(lat, lng, data);
    } catch (_) {
      return null;
    }
  }

  static WorkLocation _parse(double lat, double lng, Map<String, dynamic> data) {
    final addr = data['address'] as Map<String, dynamic>? ?? {};
    final displayName = data['display_name'] as String? ?? '';
    final district = _clean(addr['county'] as String? ??
        addr['state_district'] as String? ??
        addr['district'] as String? ?? '');
    final taluk = addr['state_district'] as String? ??
        addr['county'] as String? ??
        addr['suburb'] as String? ?? '';
    final village = addr['village'] as String? ??
        addr['town'] as String? ??
        addr['city_district'] as String? ??
        addr['hamlet'] as String? ??
        addr['suburb'] as String? ?? '';
    final locality = addr['neighbourhood'] as String? ??
        addr['quarter'] as String? ??
        addr['suburb'] as String? ?? '';
    return WorkLocation(
      lat: lat, lng: lng,
      address:  displayName,
      state:    addr['state']    as String? ?? 'Karnataka',
      district: district,
      taluk:    taluk,
      village:  village,
      locality: locality,
      pincode:  addr['postcode'] as String? ?? '',
    );
  }

  static String _clean(String d) =>
      d.replaceAll(' District', '').replaceAll(' district', '').trim();
}

class NominatimResult {
  final double lat;
  final double lng;
  final String displayName;

  const NominatimResult({required this.lat, required this.lng, required this.displayName});

  factory NominatimResult.fromJson(Map<String, dynamic> j) => NominatimResult(
    lat:         double.tryParse(j['lat'] as String? ?? '0') ?? 0,
    lng:         double.tryParse(j['lon'] as String? ?? '0') ?? 0,
    displayName: j['display_name'] as String? ?? '',
  );

  String get shortName {
    final parts = displayName.split(',');
    if (parts.length >= 2) return '${parts[0].trim()}, ${parts[1].trim()}';
    return displayName;
  }
}
