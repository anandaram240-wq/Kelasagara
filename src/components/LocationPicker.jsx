// src/components/LocationPicker.jsx
// ─────────────────────────────────────────────────────────────
// Rich Interactive Location Picker using Leaflet (via CDN)
// NO API KEY NEEDED.
// Features:
//   • Fully interactive map loaded dynamically via Leaflet CDN
//   • Click/Tap anywhere on the map to place/move the marker
//   • Drag the marker directly to fine-tune the position
//   • "Use My Current Location" button using GPS + map auto-pan
//   • Automatic reverse geocoding via Nominatim on marker movement
//   • No additional npm packages required!
// ─────────────────────────────────────────────────────────────
import { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

// Nominatim search and reverse geocode URLs
const NOMINATIM = 'https://nominatim.openstreetmap.org';
const SEARCH_BOUNDS = '11.5,74.0,18.5,78.5'; // Karnataka bounds

const toMapsUrl = (lat, lng) => `https://www.google.com/maps?q=${lat},${lng}&z=15`;

export default function LocationPicker({ value, onChange, onClose }) {
  const [query, setQuery] = useState(value?.address || '');
  const [suggestions, setSuggestions] = useState([]);
  const [selected, setSelected] = useState(value || null);
  const [loading, setLoading] = useState(false);
  const [gpsLoading, setGpsLoading] = useState(false);
  const [leafletReady, setLeafletReady] = useState(false);
  const [error, setError] = useState('');

  const mapRef = useRef(null); // Div container ref
  const mapInstance = useRef(null); // Leaflet Map object
  const markerInstance = useRef(null); // Leaflet Marker object
  const debounceRef = useRef(null);

  // 1. Dynamic CDN Loader for Leaflet
  useEffect(() => {
    // If already loaded in window
    if (window.L) {
      setLeafletReady(true);
      return;
    }

    // Load CSS
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
    document.head.appendChild(link);

    // Load JS
    const script = document.createElement('script');
    script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
    script.async = true;
    script.onload = () => {
      setLeafletReady(true);
    };
    document.body.appendChild(script);

    return () => {
      // Clean up scripts on unmount if needed (optional, we keep them cached)
    };
  }, []);

  // 2. Initialize Leaflet Map
  useEffect(() => {
    if (!leafletReady || !mapRef.current || mapInstance.current) return;

    // Default to selected coordinates, or Bengaluru, Karnataka
    const initialLat = selected?.lat || 12.9716;
    const initialLng = selected?.lng || 77.5946;
    const initialZoom = selected ? 15 : 10;

    const L = window.L;

    // Create Map
    const map = L.map(mapRef.current, {
      center: [initialLat, initialLng],
      zoom: initialZoom,
      zoomControl: true,
    });

    // Tile Layer (OpenStreetMap)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(map);

    // Custom Marker Icon (Leaflet default icons sometimes break in builds without custom asset paths)
    const customIcon = L.icon({
      iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
      shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      shadowSize: [41, 41]
    });

    // Add Draggable Marker
    const marker = L.marker([initialLat, initialLng], {
      draggable: true,
      icon: customIcon,
    }).addTo(map);

    mapInstance.current = map;
    markerInstance.current = marker;

    // Handle Marker Drag End
    marker.on('dragend', () => {
      const position = marker.getLatLng();
      handleLocationChange(position.lat, position.lng);
    });

    // Handle Map Click (moves marker directly)
    map.on('click', (e) => {
      const { lat, lng } = e.latlng;
      marker.setLatLng([lat, lng]);
      handleLocationChange(lat, lng);
    });

    // Invalidate size after map loads to prevent gray/unrendered tiles
    setTimeout(() => {
      map.invalidateSize();
    }, 200);

    return () => {
      if (mapInstance.current) {
        mapInstance.current.remove();
        mapInstance.current = null;
        markerInstance.current = null;
      }
    };
  }, [leafletReady]);

  // 3. Handle Location Change & Reverse Geocoding
  async function handleLocationChange(lat, lng) {
    setError('');
    try {
      const res = await fetch(
        `${NOMINATIM}/reverse?lat=${lat}&lon=${lng}&format=json`,
        { headers: { 'Accept-Language': 'en' } }
      );
      const data = await res.json();
      const address = data.display_name || `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
      const mapsUrl = toMapsUrl(lat, lng);

      const loc = { lat, lng, address, mapsUrl };
      setSelected(loc);
      setQuery(address);
    } catch {
      const fallbackAddress = `Location coordinates: ${lat.toFixed(5)}, ${lng.toFixed(5)}`;
      const loc = { lat, lng, address: fallbackAddress, mapsUrl: toMapsUrl(lat, lng) };
      setSelected(loc);
      setQuery(fallbackAddress);
    }
  }

  // 4. Text Search to Pan Map
  const searchAddress = async (q) => {
    if (!q || q.length < 3) return;
    setLoading(true);
    setError('');
    try {
      const res = await fetch(
        `${NOMINATIM}/search?q=${encodeURIComponent(q + ', Karnataka, India')}&format=json&limit=5&viewbox=${SEARCH_BOUNDS}&bounded=1`,
        { headers: { 'Accept-Language': 'en' } }
      );
      const data = await res.json();
      setSuggestions(data);
    } catch {
      setError('Search failed. Check your internet connection.');
    }
    setLoading(false);
  };

  function handleInput(e) {
    const q = e.target.value;
    setQuery(q);
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => searchAddress(q), 400);
  }

  function pickSuggestion(item) {
    const lat = parseFloat(item.lat);
    const lng = parseFloat(item.lon);
    const address = item.display_name;
    const mapsUrl = toMapsUrl(lat, lng);

    const loc = { lat, lng, address, mapsUrl };
    setSelected(loc);
    setQuery(address);
    setSuggestions([]);

    // Update map view & marker position
    if (mapInstance.current && markerInstance.current) {
      mapInstance.current.setView([lat, lng], 15);
      markerInstance.current.setLatLng([lat, lng]);
    }
  }

  // 5. GPS Current Location integration
  async function useCurrentLocation() {
    if (!navigator.geolocation) {
      setError('GPS is not supported by this browser.');
      return;
    }
    setGpsLoading(true);
    setError('');
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const lat = pos.coords.latitude;
        const lng = pos.coords.longitude;

        await handleLocationChange(lat, lng);

        // Pan map & update marker
        if (mapInstance.current && markerInstance.current) {
          mapInstance.current.setView([lat, lng], 15);
          markerInstance.current.setLatLng([lat, lng]);
        }
        setGpsLoading(false);
      },
      (err) => {
        setError('Location access denied. Please enable GPS permissions.');
        setGpsLoading(false);
      },
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }

  function confirm() {
    if (!selected) {
      setError('Please select a location on the map first.');
      return;
    }
    onChange(selected);
    onClose();
  }

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{
        position: 'fixed', inset: 0,
        background: 'rgba(0,0,0,0.55)',
        zIndex: 2000,
        display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
        padding: '0',
      }}
    >
      <motion.div
        initial={{ y: '100%' }}
        animate={{ y: 0 }}
        exit={{ y: '100%' }}
        transition={{ type: 'spring', damping: 26, stiffness: 260 }}
        style={{
          width: '100%', maxWidth: 600,
          background: '#fff',
          borderRadius: '20px 20px 0 0',
          padding: '24px 20px 32px',
          maxHeight: '94vh',
          overflowY: 'auto',
          boxShadow: '0 -8px 40px rgba(0,0,0,0.18)',
        }}
      >
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 18 }}>
          <div>
            <h3 style={{ margin: 0, fontFamily: "'Baloo Tamma 2',cursive", fontSize: '1.25rem' }}>
              📍 Pin Work Location
            </h3>
            <p style={{ margin: 0, fontSize: '0.78rem', color: 'var(--muted)', marginTop: 2 }}>
              Click/drag on the map OR search to place the marker exactly where work is needed
            </p>
          </div>
          <button onClick={onClose} style={{
            background: 'var(--paper)', border: 'none', borderRadius: '50%',
            width: 34, height: 34, fontSize: '1rem', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>✕</button>
        </div>

        {/* GPS Current Location Button */}
        <motion.button
          onClick={useCurrentLocation}
          disabled={gpsLoading}
          whileTap={{ scale: 0.97 }}
          style={{
            width: '100%', padding: '13px 16px',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
            background: 'linear-gradient(135deg, #1B6B45, #10B981)',
            color: '#fff', border: 'none', borderRadius: 12,
            cursor: gpsLoading ? 'wait' : 'pointer',
            fontFamily: "'DM Sans',sans-serif",
            fontWeight: 700, fontSize: '0.95rem',
            marginBottom: 14,
            boxShadow: '0 4px 14px rgba(27,107,69,0.25)',
          }}
        >
          {gpsLoading ? '⏳ Acquiring GPS Location...' : '📡 Pin Current GPS Location'}
        </motion.button>

        {/* Address Search */}
        <div style={{ position: 'relative', marginBottom: 8 }}>
          <input
            className="form-input"
            value={query}
            onChange={handleInput}
            placeholder="Search city, village, landmark to align map..."
            style={{ paddingRight: 40 }}
          />
          <span style={{
            position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)',
            fontSize: '1rem', color: 'var(--muted)', pointerEvents: 'none'
          }}>{loading ? '⏳' : '🔍'}</span>
        </div>

        {/* Suggestions Dropdown */}
        <AnimatePresence>
          {suggestions.length > 0 && (
            <motion.div
              initial={{ opacity: 0, y: -6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              style={{
                background: '#fff',
                border: '1px solid var(--border)',
                borderRadius: 12,
                overflow: 'hidden',
                marginBottom: 14,
                boxShadow: '0 4px 20px rgba(0,0,0,0.10)',
                zIndex: 2001,
                position: 'relative'
              }}
            >
              {suggestions.map((item, i) => (
                <div
                  key={i}
                  onClick={() => pickSuggestion(item)}
                  style={{
                    padding: '11px 14px',
                    cursor: 'pointer',
                    borderBottom: i < suggestions.length - 1 ? '1px solid var(--border)' : 'none',
                    fontSize: '0.82rem',
                    color: 'var(--ink)',
                    transition: 'background 0.15s',
                  }}
                  onMouseEnter={e => e.currentTarget.style.background = 'var(--paper)'}
                  onMouseLeave={e => e.currentTarget.style.background = ''}
                >
                  📍 {item.display_name}
                </div>
              ))}
            </motion.div>
          )}
        </AnimatePresence>

        {/* Error notification */}
        {error && (
          <div style={{
            padding: '10px 14px', background: '#FEF2F2', border: '1px solid #FECACA',
            borderRadius: 10, fontSize: '0.82rem', color: '#DC2626', marginBottom: 14,
          }}>
            ⚠️ {error}
          </div>
        )}

        {/* ── Leaflet Interactive Map Container ── */}
        <div style={{ position: 'relative', marginBottom: 16 }}>
          {!leafletReady && (
            <div style={{
              height: 250, background: 'var(--paper2)', display: 'flex',
              alignItems: 'center', justifyContent: 'center', borderRadius: 12,
              border: '1px solid var(--border)', fontSize: '0.9rem', color: 'var(--muted)'
            }}>
              Loading Interactive Map...
            </div>
          )}
          <div
            ref={mapRef}
            style={{
              height: 250,
              width: '100%',
              borderRadius: 12,
              border: '1px solid var(--border)',
              display: leafletReady ? 'block' : 'none',
              zIndex: 10,
            }}
          />
        </div>

        {/* Selected location feedback details */}
        {selected && (
          <div style={{
            background: 'rgba(232,89,12,0.06)',
            border: '1.5px solid rgba(232,89,12,0.25)',
            borderRadius: 12, padding: '12px 14px', marginBottom: 16,
            display: 'flex', alignItems: 'flex-start', gap: 10,
          }}>
            <span style={{ fontSize: '1.25rem' }}>📍</span>
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 700, fontSize: '0.82rem', color: 'var(--saffron)', marginBottom: 2 }}>
                Pinned Location Address
              </div>
              <div style={{ fontSize: '0.8rem', color: 'var(--ink)', lineHeight: 1.4 }}>
                {selected.address}
              </div>
              <div style={{ fontSize: '0.7rem', color: 'var(--muted)', marginTop: 4 }}>
                Coords: {selected.lat.toFixed(6)}, {selected.lng.toFixed(6)}
              </div>
            </div>
          </div>
        )}

        {/* Save button */}
        <motion.button
          onClick={confirm}
          disabled={!selected}
          whileTap={selected ? { scale: 0.97 } : {}}
          style={{
            width: '100%', padding: '14px',
            background: selected ? 'var(--saffron)' : '#D1D5DB',
            color: '#fff', border: 'none', borderRadius: 12,
            fontFamily: "'DM Sans',sans-serif",
            fontWeight: 700, fontSize: '1rem',
            cursor: selected ? 'pointer' : 'not-allowed',
            transition: 'background 0.2s',
            boxShadow: selected ? '0 4px 14px rgba(232,89,12,0.3)' : 'none',
          }}
        >
          {selected ? '✅ Save Selected Position' : 'Place map marker to save'}
        </motion.button>
      </motion.div>
    </motion.div>
  );
}
