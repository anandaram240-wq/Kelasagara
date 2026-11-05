# Kelasagara Geo Search Design

## Bounding Box Approach
Why not a geohash package? Firestore single-field inequalities are limited. Geohash libraries often require complex multi-query setups. Instead, we use a single latitude bounding box query on Firestore, followed by client-side filtering for longitude and exact distance.

### Bounding Box Formula
- `latDelta = radiusKm / 111.0`
- `lngDelta = radiusKm / (111.0 * cos(lat * pi / 180))`

We query Firestore where `discoveryLat >= minLat` and `discoveryLat <= maxLat`.

## Fetching and Filtering
We fetch a pool of up to 50 candidates from Firestore based on the latitude box.

### Client-Side Filter Chain
1. **Longitude Range**: Filter out workers outside `minLng` to `maxLng`.
2. **Freshness**: Reject workers with `LocationFreshness.stale`.
3. **Haversine**: Calculate exact distance using Haversine. Reject if > `radiusKm`.
4. **Service Radius**: Reject if distance > worker's `serviceRadiusKm`.

### Why Bounding Box Corners Exceed Radius
A square bounding box encompasses a circle. Workers in the corners of the box will be further than the exact radius (up to `sqrt(2) * radius`). The Haversine filter ensures we drop these corner cases and only keep those within the exact circular radius.

## Pagination in GPS Mode
Because we do client-side filtering, we might fetch 50 workers from Firestore but only 10 pass the filter. The `cursor` for pagination is simply the last document snap fetched from Firestore. When the user requests the next page, we resume the `discoveryLat` inequality query from that cursor.

## MatrixService Integration
With the introduction of `discoveryLat` and `discoveryLng`, we now pass real coordinates to the `MatrixService` to calculate precise road distances and ETAs, replacing previously stubbed logic.

## Ranking Algorithm
Sorted in order:
1. Exact Road Distance (via Matrix)
2. Exact Geo Distance (Haversine fallback)
3. Worker Rating
4. Number of Completed Jobs
5. Verification Status
