/// Canonical work location model — used in Job creation, Firestore doc,
/// worker feed, job detail, navigation. ONE definition, used everywhere.
class WorkLocation {
  final double lat;
  final double lng;
  final String address;
  final String state;
  final String district;
  final String taluk;
  final String village;
  final String locality;
  final String pincode;

  const WorkLocation({
    required this.lat,
    required this.lng,
    this.address  = '',
    this.state    = '',
    this.district = '',
    this.taluk    = '',
    this.village  = '',
    this.locality = '',
    this.pincode  = '',
  });

  bool get isValid =>
      lat != 0.0 && lng != 0.0 &&
      lat.abs() <= 90 && lng.abs() <= 180 &&
      address.isNotEmpty;

  String get shortLabel {
    if (village.isNotEmpty && taluk.isNotEmpty) return '$village, $taluk';
    if (taluk.isNotEmpty && district.isNotEmpty) return '$taluk, $district';
    if (district.isNotEmpty) return district;
    return address.isNotEmpty ? address : 'Location selected';
  }

  Map<String, dynamic> toMap() => {
    'lat':      lat,
    'lng':      lng,
    'address':  address,
    'state':    state,
    'district': district,
    'taluk':    taluk,
    'village':  village,
    'locality': locality,
    'pincode':  pincode,
  };

  factory WorkLocation.fromMap(Map<String, dynamic> m) => WorkLocation(
    lat:      (m['lat']  as num?)?.toDouble() ?? 0.0,
    lng:      (m['lng']  as num?)?.toDouble() ?? 0.0,
    address:  m['address']  as String? ?? '',
    state:    m['state']    as String? ?? '',
    district: m['district'] as String? ?? '',
    taluk:    m['taluk']    as String? ?? '',
    village:  m['village']  as String? ?? '',
    locality: m['locality'] as String? ?? '',
    pincode:  m['pincode']  as String? ?? '',
  );

  WorkLocation copyWith({
    double? lat, double? lng,
    String? address, String? state, String? district,
    String? taluk, String? village, String? locality, String? pincode,
  }) => WorkLocation(
    lat:      lat      ?? this.lat,
    lng:      lng      ?? this.lng,
    address:  address  ?? this.address,
    state:    state    ?? this.state,
    district: district ?? this.district,
    taluk:    taluk    ?? this.taluk,
    village:  village  ?? this.village,
    locality: locality ?? this.locality,
    pincode:  pincode  ?? this.pincode,
  );
}
