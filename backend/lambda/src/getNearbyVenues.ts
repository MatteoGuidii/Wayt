import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { queryNearbyFused } from "./db";
import { haversineDistance, success, badRequest, serverError } from "./shared";
import { FusedEstimate } from "./signals/types";
import { computeVenueBusyness, ComputeInput } from "./computeVenueBusyness";
import { createLogger } from "./logger";

/** Max allowed search radius (10 km). */
const MAX_RADIUS = 10_000;
/**
 * Max venues to compute on-demand per request.
 * Limits latency — the rest will be computed on subsequent requests.
 */
const MAX_INLINE_COMPUTES = 50;

/** POST request body shape. */
interface NearbyVenuesBody {
  lat: number;
  lng: number;
  radius?: number;
  timezone?: string;
  venues?: ComputeInput[];
}

/**
 * GET or POST /v1/venues/nearby
 *
 * Returns fused busyness estimates for venues near the given coordinates.
 *
 * GET: params via query string (venues JSON-encoded, batched to 20 for URL limit).
 * POST: params via JSON body (no batching needed — send all venues at once).
 *
 * The `venues` field is an optional array of venue objects
 * ({ venueId, venueName, lat, lng }) that the iOS app discovered via MapKit.
 * For any venue not in the fused cache, we compute on-demand.
 */
export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getNearbyVenues", event, context);
  const done = log.startTimer("Handler complete");
  try {
    // Parse params from query string (GET) or body (POST)
    const { lat, lng, radius, timezone, clientVenues } = parseParams(event);

    if (isNaN(lat) || isNaN(lng)) {
      return badRequest("Missing or invalid lat/lng parameters");
    }

    log.info("Fetching nearby venues", { lat, lng, radius, method: event.httpMethod });

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

    // Step 2: Compute on-demand for venues not in cache (up to MAX_INLINE_COMPUTES)
    const missing = clientVenues.filter((v) => !nearbyFused.has(v.venueId));
    const toCompute = missing.slice(0, MAX_INLINE_COMPUTES);

    if (toCompute.length > 0) {
      log.info("Computing on-demand estimates", { count: toCompute.length, totalMissing: missing.length });
      const computeResults = await Promise.all(
        toCompute.map((v) => computeVenueBusyness({ ...v, timezone }))
      );
      for (const result of computeResults) {
        nearbyFused.set(result.venueId, result);
      }
    }

    // Step 3: Return results
    const venues = Array.from(nearbyFused.values());

    done({ venueCount: venues.length, cached: nearbyFused.size - toCompute.length, computed: toCompute.length });
    return success({ venues });
  } catch (err) {
    log.error("Failed to fetch nearby venues", undefined, err);
    return serverError("Failed to fetch nearby venues");
  }
}

/** Extract lat/lng/radius/timezone/venues from either query string or JSON body. */
function parseParams(event: APIGatewayProxyEvent): {
  lat: number;
  lng: number;
  radius: number;
  timezone: string;
  clientVenues: ComputeInput[];
} {
  if (event.httpMethod === "POST" && event.body) {
    const body: NearbyVenuesBody = JSON.parse(event.body);
    const parsedRadius = body.radius ?? 2000;
    return {
      lat: body.lat,
      lng: body.lng,
      radius: Math.min(isNaN(parsedRadius) ? 2000 : parsedRadius, MAX_RADIUS),
      timezone: body.timezone ?? "UTC",
      clientVenues: body.venues ?? [],
    };
  }

  // GET — read from query string (backward compatible)
  const params = event.queryStringParameters ?? {};
  const parsedRadius = parseInt(params.radius ?? "2000", 10);
  let clientVenues: ComputeInput[] = [];
  if (params.venues) {
    try {
      clientVenues = JSON.parse(params.venues) as ComputeInput[];
    } catch {
      // Invalid JSON — skip client venues
    }
  }
  return {
    lat: parseFloat(params.lat ?? ""),
    lng: parseFloat(params.lng ?? ""),
    radius: Math.min(isNaN(parsedRadius) ? 2000 : parsedRadius, MAX_RADIUS),
    timezone: params.timezone ?? "UTC",
    clientVenues,
  };
}
