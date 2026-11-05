#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Kelasagara Self-Hosted Valhalla Routing Engine Setup (Karnataka Extract)
# ==============================================================================
# Architecture: High-throughput, zero-cost Valhalla routing with custom Indian
# two-wheeler costing (living_streets, tracks, service roads enabled).
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_FILES_DIR="${SCRIPT_DIR}/custom_files"
PBF_URL="https://download.geofabrik.de/asia/india/karnataka-latest.osm.pbf"
PBF_FILE="${CUSTOM_FILES_DIR}/karnataka-latest.osm.pbf"

mkdir -p "${CUSTOM_FILES_DIR}"

echo "=========================================================="
echo "🚲 Kelasagara Self-Hosted Valhalla Engine Setup (Karnataka)"
echo "=========================================================="

if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH."
    exit 1
fi

if [ ! -f "${PBF_FILE}" ]; then
    echo "📥 Downloading Karnataka OSM extract from Geofabrik..."
    echo "Source: ${PBF_URL}"
    curl -L --progress-bar -o "${PBF_FILE}" "${PBF_URL}"
    echo "✅ Download complete: $(ls -lh "${PBF_FILE}" | awk '{print $5}')"
else
    echo "✅ Found existing OSM extract: $(ls -lh "${PBF_FILE}" | awk '{print $5}')"
fi

echo "🚀 Starting Valhalla container via Docker Compose..."
cd "${SCRIPT_DIR}"
docker compose up -d

echo "⏳ Waiting for Valhalla tile build & routing service readiness on port 8002..."
MAX_ATTEMPTS=60
ATTEMPT=0
READY=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s -f "http://localhost:8002/status" > /dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 3
    ATTEMPT=$((ATTEMPT + 1))
    echo -n "."
done
echo ""

if [ "$READY" = true ]; then
    echo "✅ Valhalla is LIVE and healthy on http://localhost:8002"
    echo ""
    echo "🧪 Testing 2-Wheeler Route in Bengaluru (MG Road -> Indiranagar)..."
    TEST_RESPONSE=$(curl -s "http://localhost:8002/route" \
      -H "Content-Type: application/json" \
      -d '{
        "locations": [
          {"lat": 12.9716, "lon": 77.5946, "type": "break"},
          {"lat": 12.9784, "lon": 77.6408, "type": "break"}
        ],
        "costing": "motorcycle",
        "costing_options": {
          "motorcycle": {
            "use_living_streets": 1.0,
            "use_tracks": 0.85,
            "service_penalty": 0.0,
            "top_speed": 48
          }
        },
        "directions_options": {"units": "kilometers"}
      }')
    
    if echo "$TEST_RESPONSE" | grep -q "trip"; then
        echo "🎉 Routing Test PASSED! Sample Route Generated Successfully."
        echo "Point your Flutter app to: VALHALLA_BASE_URL=http://<YOUR_SERVER_IP>:8002/route"
    else
        echo "⚠️ Valhalla responded, but check route payload: $TEST_RESPONSE"
    fi
else
    echo "⚠️ Valhalla container started, but tiles are still compiling."
    echo "Run 'docker logs -f kelasagara_valhalla_karnataka' to monitor compilation progress."
fi
