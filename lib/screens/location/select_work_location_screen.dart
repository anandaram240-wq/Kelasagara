import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_colors.dart';
import '../../models/work_location.dart';
import '../../services/location_service.dart';
import '../../services/nominatim_service.dart';

/// Full-screen map picker. Returns WorkLocation when hirer confirms.
/// Supports: current location, address search, manual pin placement.
class SelectWorkLocationScreen extends StatefulWidget {
  final WorkLocation? initial;
  const SelectWorkLocationScreen({super.key, this.initial});

  @override
  State<SelectWorkLocationScreen> createState() => _SelectWorkLocationScreenState();
}

class _SelectWorkLocationScreenState extends State<SelectWorkLocationScreen> {
  // Default center: Bengaluru, Karnataka (state capital)
  static const _defaultCenter = LatLng(12.9716, 77.5946);

  final _mapCtrl  = MapController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  LatLng _center = _defaultCenter;
  WorkLocation? _selected;

  bool _loadingGps      = false;
  bool _loadingGeocode  = false;
  bool _showSearch      = false;
  bool _showResults     = false;
  String? _geocodeError;

  List<NominatimResult> _searchResults = [];
  Timer? _debounce;
  Timer? _geocodeDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null && widget.initial!.isValid) {
      _center   = LatLng(widget.initial!.lat, widget.initial!.lng);
      _selected = widget.initial;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _geocodeDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── GPS current location ─────────────────────────────────────────────────
  Future<void> _useCurrentLocation() async {
    setState(() { _loadingGps = true; _geocodeError = null; });
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() => _loadingGps = false);
      _showMsg('Location permission denied. Use search or manual pin instead.');
      return;
    }
    final ll = LatLng(pos.latitude, pos.longitude);
    _mapCtrl.move(ll, 16);
    setState(() { _center = ll; _loadingGps = false; });
    await _reverseGeocode(ll.latitude, ll.longitude);
  }

  // ── Reverse geocode with debounce ────────────────────────────────────────
  void _onMapPositionChanged(MapCamera cam, bool hasGesture) {
    if (!hasGesture) return;
    setState(() { _center = cam.center; _loadingGeocode = true; _geocodeError = null; });
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 900), () {
      _reverseGeocode(cam.center.latitude, cam.center.longitude);
    });
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    setState(() { _loadingGeocode = true; _geocodeError = null; });
    try {
      final loc = await NominatimService.reverseGeocode(lat, lng);
      if (!mounted) return;
      if (loc == null) {
        setState(() {
          _loadingGeocode = false;
          _geocodeError = 'Unable to identify this address. Try again or adjust the pin.';
          _selected = null;
        });
      } else {
        setState(() { _loadingGeocode = false; _selected = loc; _geocodeError = null; });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingGeocode = false; _geocodeError = 'Geocoding failed. Check connection.'; });
    }
  }

  // ── Address search with debounce ─────────────────────────────────────────
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) { setState(() { _searchResults = []; _showResults = false; }); return; }
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final results = await NominatimService.search(q);
      if (!mounted) return;
      setState(() { _searchResults = results; _showResults = results.isNotEmpty; });
    });
  }

  void _selectSearchResult(NominatimResult r) {
    final ll = LatLng(r.lat, r.lng);
    _mapCtrl.move(ll, 16);
    setState(() {
      _center = ll;
      _searchResults = [];
      _showResults   = false;
      _showSearch    = false;
      _searchCtrl.clear();
      _loadingGeocode = true;
    });
    _searchFocus.unfocus();
    _reverseGeocode(r.lat, r.lng);
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      backgroundColor: AppColors.textMed,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [

        // ── OSM Map (flutter_map + OpenStreetMap tiles) ─────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 14,
            onPositionChanged: _onMapPositionChanged,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'in.kelasagara.app',
              maxZoom: 19,
            ),
          ],
        ),

        // ── Center pin marker ───────────────────────────────────────────────
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.location_pin, size: 48, color: AppColors.red,
              shadows: const [Shadow(blurRadius: 8, color: Colors.black38)]),
            const SizedBox(height: 24), // offset so pin tip is at center
          ]),
        ),

        // ── Top App Bar ─────────────────────────────────────────────────────
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 40, height: 40, decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
              ), child: const Icon(Icons.arrow_back, size: 20, color: AppColors.textHead)),
            ),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () => setState(() { _showSearch = true; _searchFocus.requestFocus(); }),
              child: _showSearch
                ? Container(height: 44, decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
                  ), child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search village, area, landmark, pincode...',
                      hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textFaint),
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.primary),
                      suffixIcon: GestureDetector(
                        onTap: () { _searchCtrl.clear(); setState(() { _showSearch = false; _searchResults = []; _showResults = false; }); },
                        child: const Icon(Icons.close, size: 16, color: AppColors.textFaint),
                      ),
                      border: InputBorder.none, isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead),
                  ))
                : Container(height: 44, decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
                  ), padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
                    const Icon(Icons.search, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('Search work location...', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textFaint)),
                  ])),
            )),
          ]),
        )),

        // ── Search results dropdown ─────────────────────────────────────────
        if (_showResults)
          SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 70, 12, 0),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12)]),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
                itemBuilder: (_, i) {
                  final r = _searchResults[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined, size: 18, color: AppColors.primary),
                    title: Text(r.shortName, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                    subtitle: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint)),
                    onTap: () => _selectSearchResult(r),
                  );
                },
              ),
            ),
          )),

        // ── GPS Button ──────────────────────────────────────────────────────
        Positioned(right: 16, bottom: 260, child: GestureDetector(
          onTap: _loadingGps ? null : _useCurrentLocation,
          child: Container(width: 48, height: 48, decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
          ), child: _loadingGps
            ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
            : const Icon(Icons.my_location, color: AppColors.primary, size: 24)),
        )),

        // ── Bottom Confirmation Card ────────────────────────────────────────
        Positioned(bottom: 0, left: 0, right: 0, child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4))],
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle bar
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 12),

            Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppColors.primaryPale, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.location_on, color: AppColors.primary, size: 20)),
              const SizedBox(width: 10),
              Text('Work Location', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textHead)),
              const Spacer(),
              if (_loadingGeocode) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            ]),
            const SizedBox(height: 10),

            if (_geocodeError != null) ...[
              Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.red),
                const SizedBox(width: 6),
                Expanded(child: Text(_geocodeError!, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.red))),
              ]),
              const SizedBox(height: 8),
            ] else if (_selected != null) ...[
              Text(_selected!.address.isNotEmpty ? _selected!.address : 'Move map to refine location',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textBody), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                if (_selected!.district.isNotEmpty) _chip('📍 ${_selected!.district}'),
                if (_selected!.taluk.isNotEmpty)    _chip('🏘 ${_selected!.taluk}'),
                if (_selected!.village.isNotEmpty)  _chip('🌿 ${_selected!.village}'),
                if (_selected!.pincode.isNotEmpty)  _chip('📮 ${_selected!.pincode}'),
              ]),
              const SizedBox(height: 6),
              Text('${_center.latitude.toStringAsFixed(5)}°N, ${_center.longitude.toStringAsFixed(5)}°E',
                style: GoogleFonts.plusJakartaSans(fontSize: 9, color: AppColors.textFaint)),
            ] else if (!_loadingGeocode) ...[
              Text('Move the map to select the exact work location.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textLight)),
            ],
            const SizedBox(height: 14),

            SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
              onPressed: (_selected != null && _selected!.isValid && !_loadingGeocode)
                ? () => Navigator.pop(context, _selected)
                : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.divider,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Confirm Work Location ✓',
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
            )),

            const SizedBox(height: 6),
            Center(child: Text('Move the map to pinpoint the exact work site',
              style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textFaint))),
          ]),
        )),
      ]),
    );
  }

  Widget _chip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
    child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textBody)),
  );
}
