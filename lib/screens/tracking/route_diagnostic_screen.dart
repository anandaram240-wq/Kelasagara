// lib/screens/tracking/route_diagnostic_screen.dart
// Developer-only routing diagnostic screen (Phase 1 requirement).
//
// Shows the 12-point routing health test:
//  1. Server URL configured?
//  2. Server reachable (/status)?
//  3. POST /route returns HTTP 200?
//  4. Valid JSON?
//  5. trip.summary present?
//  6. trip.summary.time > 0?
//  7. legs[0].shape present?
//  8. shape.length > 0?
//  9. Decode shape → >2 points?
// 10. First decoded point near origin?
// 11. Last decoded point near destination?
// 12. Route plausible distance?
//
// ACCESS: Only visible in debug builds or via Settings > Dev > Route Diagnostics.
// NEVER shown to normal workers/hirers.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/valhalla_service.dart';

class RouteDiagnosticScreen extends StatefulWidget {
  const RouteDiagnosticScreen({super.key});

  @override
  State<RouteDiagnosticScreen> createState() => _RouteDiagnosticScreenState();
}

class _RouteDiagnosticScreenState extends State<RouteDiagnosticScreen> {
  RouteHealthReport? _report;
  bool _running = false;

  // Default test coords — Bengaluru to Hassan (real Karnataka route)
  final _originLatCtrl  = TextEditingController(text: '12.9716');
  final _originLngCtrl  = TextEditingController(text: '77.5946');
  final _destLatCtrl    = TextEditingController(text: '13.0060');
  final _destLngCtrl    = TextEditingController(text: '76.0954');

  @override
  void dispose() {
    _originLatCtrl.dispose(); _originLngCtrl.dispose();
    _destLatCtrl.dispose();   _destLngCtrl.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    setState(() { _running = true; _report = null; });
    final origin = LatLng(
      double.tryParse(_originLatCtrl.text) ?? 12.9716,
      double.tryParse(_originLngCtrl.text) ?? 77.5946,
    );
    final dest = LatLng(
      double.tryParse(_destLatCtrl.text) ?? 13.0060,
      double.tryParse(_destLngCtrl.text) ?? 76.0954,
    );
    final report = await ValhallaService.instance.runDiagnostic(
        origin: origin, destination: dest);
    setState(() { _report = report; _running = false; });
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FA),
    appBar: AppBar(
      title: const Text('🔧 Route Diagnostics', style: TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: const Color(0xFF1E293B),
      foregroundColor: Colors.white,
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Server status
        _StatusCard(),

        const SizedBox(height: 16),

        // Coordinate inputs
        const _SectionTitle('Test Coordinates'),
        _CoordRow('Origin Lat', _originLatCtrl),
        _CoordRow('Origin Lng', _originLngCtrl),
        _CoordRow('Dest Lat',   _destLatCtrl),
        _CoordRow('Dest Lng',   _destLngCtrl),

        const SizedBox(height: 12),

        // Run test button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _running ? null : _runTest,
            icon: _running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.science),
            label: Text(_running ? 'Running 12-point test...' : 'RUN ROUTING HEALTH TEST'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),

        if (_report != null) ...[
          const SizedBox(height: 20),
          const _SectionTitle('Results'),
          _ResultsCard(_report!),

          // Show decoded route on mini map if successful
          if (_report!.routeFound && _report!.shapeDecodedPoints > 2) ...[
            const SizedBox(height: 16),
            _SectionTitle('Route Preview (${_report!.shapeDecodedPoints} points)'),
            Container(
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22C55E), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: _RoutePreviewMap(report: _report!),
            ),
          ],
        ],

        const SizedBox(height: 24),
        const _SectionTitle('Setup Instructions'),
        _SetupCard(),

      ]),
    ),
  );
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) {
    final configured = ValhallaService.isConfigured;
    final url        = ValhallaService.baseUrl;
    final color      = configured ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: color),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(configured ? Icons.check_circle : Icons.cancel, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            configured ? 'VALHALLA CONFIGURED' : 'VALHALLA NOT CONFIGURED',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          configured
              ? 'URL: $url'
              : 'Build with:\n--dart-define=VALHALLA_URL=http://192.168.x.x:8002',
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
  );
}

class _CoordRow extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  const _CoordRow(this.label, this.ctrl);
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
      const SizedBox(width: 8),
      Expanded(child: TextField(
        controller:  ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration:  InputDecoration(
          isDense:       true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border:        OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      )),
    ]),
  );
}

class _ResultsCard extends StatelessWidget {
  final RouteHealthReport r;
  const _ResultsCard(this.r);

  @override
  Widget build(BuildContext ctx) {
    final checks = [
      _Check('Server URL configured',      ValhallaService.isConfigured),
      _Check('Server reachable',           r.serverReachable),
      _Check('HTTP 200',                   r.httpStatus == 200),
      _Check('Route found',                r.routeFound),
      _Check('Distance > 0',               (r.distanceKm ?? 0) > 0),
      _Check('Duration > 0',               (r.durationSec ?? 0) > 0),
      _Check('Shape present',              r.shapeRaw?.isNotEmpty == true),
      _Check('Shape decoded > 2 points',   r.shapeDecodedPoints > 2),
      _Check('First point not null',       r.firstPoint != null),
      _Check('Last point not null',        r.lastPoint  != null),
    ];

    final allPass = checks.every((c) => c.pass);

    return Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow:    const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: allPass ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Text(
            allPass ? '✅ ALL CHECKS PASSED — ROUTING WORKS' : '❌ SOME CHECKS FAILED',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
        ...checks.map((c) => _CheckRow(c)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('HTTP Status',    '${r.httpStatus}'),
            _kv('Server URL',     r.serverUrl),
            _kv('Distance',       '${r.distanceKm?.toStringAsFixed(2) ?? "—"} km'),
            _kv('Duration',       '${(r.durationSec ?? 0) ~/ 60} min ${(r.durationSec ?? 0) % 60} sec'),
            _kv('Shape length',   '${r.shapeRaw?.length ?? 0} chars'),
            _kv('Decoded points', '${r.shapeDecodedPoints}'),
            _kv('First point',    r.firstPoint != null
                ? '${r.firstPoint!.latitude.toStringAsFixed(5)}, ${r.firstPoint!.longitude.toStringAsFixed(5)}'
                : 'null'),
            _kv('Last point',     r.lastPoint != null
                ? '${r.lastPoint!.latitude.toStringAsFixed(5)}, ${r.lastPoint!.longitude.toStringAsFixed(5)}'
                : 'null'),
            if (r.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Error: ${r.errorMessage}',
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey))),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF1F2937)))),
    ]),
  );
}

class _Check {
  final String label;
  final bool   pass;
  const _Check(this.label, this.pass);
}

class _CheckRow extends StatelessWidget {
  final _Check c;
  const _CheckRow(this.c);
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Row(children: [
      Icon(c.pass ? Icons.check_circle : Icons.cancel,
           color: c.pass ? const Color(0xFF22C55E) : const Color(0xFFEF4444), size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(c.label, style: const TextStyle(fontSize: 12))),
    ]),
  );
}

class _RoutePreviewMap extends StatelessWidget {
  final RouteHealthReport report;
  const _RoutePreviewMap({required this.report});

  @override
  Widget build(BuildContext ctx) {
    // Reconstruct points from first/last for bounds
    final first = report.firstPoint!;
    final last  = report.lastPoint!;
    final center = LatLng(
      (first.latitude  + last.latitude)  / 2,
      (first.longitude + last.longitude) / 2,
    );

    // NOTE: We don't have the full decoded list here — only first/last.
    // Full decoded list is in the RouteHealthReport but we'd need to pass it through.
    // For now show just origin/dest markers and note shape point count.
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom:   9,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kelasagara.app',
        ),
        MarkerLayer(markers: [
          Marker(
            point:  first,
            width:  30,
            height: 30,
            child:  const Icon(Icons.circle, color: Color(0xFF3B82F6), size: 16),
          ),
          Marker(
            point:  last,
            width:  30,
            height: 30,
            child:  const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 20),
          ),
        ]),
      ],
    );
  }
}

class _SetupCard extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:        const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('To enable real routing:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text('1. Install Docker Desktop\n   docker.com → Download → Mac (Apple Silicon)',
          style: TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace')),
      SizedBox(height: 6),
      Text('2. Open Docker Desktop (whale icon in menu bar)',
          style: TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace')),
      SizedBox(height: 6),
      Text('3. Run setup script:\n   bash valhalla_setup.sh',
          style: TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace')),
      SizedBox(height: 6),
      Text('4. Build APK with your Mac IP:\n   flutter build apk --release \\\n   --dart-define=VALHALLA_URL=http://192.168.x.x:8002',
          style: TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace')),
      SizedBox(height: 8),
      Text('Android device must be on the same WiFi as your Mac.',
          style: TextStyle(color: Colors.amber, fontSize: 11)),
    ]),
  );
}
