# KELASAGARA V20.0 — MAP TILE PROVIDER FIX & WATERMARK ELIMINATION AUDIT

**Date:** 2026-10-25  
**Target File:** `lib/screens/tracking/hirer_tracking_screen.dart`  
**Configuration Authority:** `lib/services/navigation/map_tile_configuration.dart`  
**Automated Regression Test:** `test/v20_map_tile_configuration_test.dart`

---

## 1. Incident Root-Cause Analysis

### The Failure Symptom
In user-submitted screenshots (`media_1792900499800_de7d4c3a.jpg` and `media_1792900499800_49acfafe.jpg`), the entire map background in `HirerTrackingScreen` was covered with repetitive gray watermark raster tiles stamped with:
```
API KEY REQUIRED
carto.com/basemaps/apikey
```

### The Code Flaw
In `lib/screens/tracking/hirer_tracking_screen.dart` (lines 185–191), the map tile layer was hardcoded directly to the unauthenticated CARTO Voyager endpoint:
```dart
// BROKEN IMPLEMENTATION:
TileLayer(
  urlTemplate:
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
  subdomains: const ['a', 'b', 'c', 'd'],
  userAgentPackageName: 'com.kelasagaara.app',
  retinaMode: RetinaMode.isHighDensity(context),
),
```

CARTO recently enforced authenticated-only access on `basemaps.cartocdn.com`. When requests arrive without a `?key=` query parameter, CARTO returns watermarked raster tiles rather than standard base imagery. Furthermore, the hardcoded layer completely bypassed the existing canonical `MapTileConfiguration` class and lacked OpenStreetMap copyright attribution.

---

## 2. Structural Correction

### 2.1 Reconciled Canonical Configuration
In `lib/screens/tracking/hirer_tracking_screen.dart`, the hardcoded tile layer was replaced with a dynamic configuration resolver using `MapTileConfiguration.instance.validateConfiguration()`:

```dart
// RESOLVED IMPLEMENTATION:
Builder(builder: (context) {
  final mapConfig =
      MapTileConfiguration.instance.validateConfiguration();
  return TileLayer(
    urlTemplate: mapConfig.urlTemplate ??
        MapTileConfiguration.osmTileUrlTemplate,
    subdomains: mapConfig.subdomains,
    userAgentPackageName: 'com.kelasagaara.kelasagaara',
    retinaMode: RetinaMode.isHighDensity(context),
    maxZoom: 19,
  );
}),
RichAttributionWidget(
  attributions: [
    TextSourceAttribution(
      '© OpenStreetMap contributors',
      onTap: () => launchUrl(
        Uri.parse('https://openstreetmap.org/copyright'),
        mode: LaunchMode.externalApplication,
      ),
    ),
  ],
),
```

### 2.2 Hardened Fallback in MapTileConfiguration
In `lib/services/navigation/map_tile_configuration.dart`, `validateConfiguration` was updated to gracefully fall back to `osmTileUrlTemplate` (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`) whenever a candidate `CARTO_API_KEY` is missing, blank, whitespace, or a placeholder token (e.g. `your_key`, `carto_api_key`), when `allowOsmFallback` is true.

---

## 3. Verification & Evidence

Automated test suite `test/v20_map_tile_configuration_test.dart` executes 4 distinct assertions:
1. **OSM Fallback Guarantee:** When no keys are injected, configuration resolves to `MapTileProvider.osm` pointing to `tile.openstreetmap.org` without `cartocdn.com` URLs or subdomains.
2. **Placeholder Rejection:** Evaluates 9 candidate placeholder strings (`your_key`, `your_carto_key`, `carto_api_key`, `<build_time_key>`, `<redacted>`, `placeholder`, whitespace, empty, short strings) and confirms all cleanly fall back to OSM.
3. **Strict Validation Enforcement:** Rejects missing keys with `MapTileProvider.unconfigured` when `allowOsmFallback` is explicitly disabled.
4. **URL Key Parameter Integrity:** When a valid alphanumeric CARTO key is provided, constructs `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png?key=KEY` with exactly one `?key=` parameter.

**Test Run Output:**
```
00:00 +0: Default configuration safely falls back to OpenStreetMap standard tiles without watermarks [PASS]
00:00 +1: Rejects placeholder CARTO keys and falls back to OSM [PASS]
00:00 +2: Rejects missing CARTO key when OSM fallback is disallowed [PASS]
00:00 +3: Constructs valid CARTO Voyager URL with single ?key= parameter when genuine key provided [PASS]
00:00 +4: All tests passed!
```
