import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import { queryNearbyFused, putItem, getItem, activeAreaPK } from "./db";
import { encode } from "./geohash";
import { haversineDistance, success, badRequest, serverError } from "./shared";
import { FusedEstimate } from "./signals/types";
import { computeVenueBusyness, ComputeInput } from "./computeVenueBusyness";

/** Max allowed search radius (10 km). */
const MAX_RADIUS = 10_000;
/** TTL for active area tracking (30 minutes). */
const ACTIVE_AREA_TTL_SECONDS = 30 * 60;
/**
 * Max venues to compute on-demand per request.
 * Limits latency — the rest will be computed on subsequent requests.
 */
const MAX_INLINE_COMPUTES = 10;

/**
 * GET /v1/venues/nearby?lat=&lng=&radius=&venues=
 *
 * Returns fused busyness estimates for venues near the given coordinates.
 *
 * The `venues` query param is an optional JSON array of venue objects
 * ({ id, name, lat, lng }) that the iOS app discovered via MapKit.
 * For any venue not in the fused cache, we compute on-demand.
 */
export async function handler(
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> {
  try {
    const params = event.queryStringParameters ?? {};
    const lat = parseFloat(params.lat ?? "");
    const lng = parseFloat(params.lng ?? "");
    const parsedRadius = parseInt(params.radius ?? "2000", 10);
    const radius = Math.min(isNaN(parsedRadius) ? 2000 : parsedRadius, MAX_RADIUS);

    if (isNaN(lat) || isNaN(lng)) {
      return badRequest("Missing or invalid lat/lng parameters");
    }

    // Step 1: Query cached fused estimates from geohash neighborhood
    const cachedItems = await queryNearbyFused(lat, lng);

    // Filter by haversine distance and check TTL
    const nowSeconds = Math.floor(Date.now() / 1000);
    const nearbyFused = new Map<string, FusedEstimate>();

    for (const item of cachedItems) {
      const itemLat = item.lat as number;
      const itemLng = item.lng as number;
      const ttl = item.ttl as number | undefined;

      // Skip expired items
      if (ttl && ttl < nowSeconds) continue;

      // Skip items outside radius
      const dist = haversineDistance(lat, lng, itemLat, itemLng);
      if (dist > radius) continue;

      const venueId = item.venueId as string;
      nearbyFused.set(venueId, {
        venueId,
        busynessScore: item.busynessScore as number,
        confidence: item.confidence as FusedEstimate["confidence"],
        reportCount: item.reportCount as number,
        waitMinutes: (item.waitMinutes as number | null) ?? null,
        sourceCount: item.sourceCount as number,
        sources: item.sources as string[],
        conflictDetected: item.conflictDetected as boolean,
        computedAt: item.computedAt as string,
      });
    }

    // Step 2: Parse venue list from client (if provided) and compute missing
    let clientVenues: ComputeInput[] = [];
    if (params.venues) {
      try {
        clientVenues = JSON.parse(decodeURIComponent(params.venues)) as ComputeInput[];
      } catch {
        // Invalid JSON — skip client venues
      }
    }

    // Compute on-demand for venues not in cache (up to MAX_INLINE_COMPUTES)
    const missing = clientVenues.filter((v) => !nearbyFused.has(v.venueId));
    const toCompute = missing.slice(0, MAX_INLINE_COMPUTES);

    if (toCompute.length > 0) {
      const computeResults = await Promise.all(
        toCompute.map((v) => computeVenueBusyness(v))
      );
      for (const result of computeResults) {
        nearbyFused.set(result.venueId, result);
      }
    }

    // Step 3: Track active area — only write if geohash changed or entry expired
    const geohash = encode(lat, lng);
    const areaPK = activeAreaPK(geohash);
    const existing = await getItem(areaPK, "META");
    const isExpiredOrMissing = !existing || ((existing.ttl as number) ?? 0) < nowSeconds;
    if (isExpiredOrMissing) {
      await putItem({
        PK: areaPK,
        SK: "META",
        lastQueried: new Date().toISOString(),
        lat,
        lng,
        ttl: nowSeconds + ACTIVE_AREA_TTL_SECONDS,
      });
    }

    // Step 4: Return results
    const venues = Array.from(nearbyFused.values());

    return success({ venues });
  } catch (err) {
    console.error("[getNearbyVenues] Error:", err);
    return serverError("Failed to fetch nearby venues");
  }
}
