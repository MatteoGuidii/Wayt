import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { LambdaClient, InvokeCommand } from "@aws-sdk/client-lambda";
import { queryNearbyFused, batchGetItems } from "./db";
import { haversineDistance, success, badRequest, serverError } from "./shared";
import { FusedEstimate } from "./signals/types";
import { ComputeInput } from "./computeVenueBusyness";
import { emptyEstimate, foursquareConfidenceLevel } from "./signals/fusion";
import { computeTimeAwareBusyness } from "./signals/foursquare";
import { isOpenNow, CachedGoogleHours, GoogleOpenPeriod } from "./signals/google";
import { createLogger } from "./logger";

/** Max allowed search radius (10 km). */
const MAX_RADIUS = 10_000;

const BACKGROUND_FUNCTION = process.env.COLD_VENUES_FUNCTION ?? "";
const lambdaClient = new LambdaClient({});

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
 * Two-tier fast path:
 * 1. Return cached fused estimates from DynamoDB geohash (instant).
 * 2. For missing venues with cached Foursquare raw data (FSQDATA#CURRENT),
 *    compute scores inline using pure math (no writes, no API calls).
 * 3. Remaining cold venues dispatched to background Lambda.
 *
 * Response time target: <500ms regardless of venue count.
 */
export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getNearbyVenues", event, context);
  const done = log.startTimer("Handler complete");
  try {
    const { lat, lng, radius, timezone, clientVenues } = parseParams(event);

    if (isNaN(lat) || isNaN(lng)) {
      return badRequest("Missing or invalid lat/lng parameters");
    }

    log.info("Fetching nearby venues", { lat, lng, radius, method: event.httpMethod });

    // Step 1: Query cached fused estimates from geohash neighborhood (fast DynamoDB-only)
    const cachedItems = await queryNearbyFused(lat, lng);

    const nowMs = Date.now();
    const nowSeconds = Math.floor(nowMs / 1000);
    const nearbyFused = new Map<string, FusedEstimate>();

    for (const item of cachedItems) {
      const itemLat = item.lat as number;
      const itemLng = item.lng as number;
      const ttl = item.ttl as number | undefined;

      if (ttl && ttl < nowSeconds) continue;

      // Skip cached empty estimates (sourceCount === 0) — treat as cache miss so
      // the background Lambda retries with improved matching thresholds.
      const sourceCount = item.sourceCount as number;
      if (sourceCount === 0) continue;

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
        isOpen: (item.isOpen as boolean | null) ?? null,
        hoursToday: (item.hoursToday as string | null) ?? null,
        businessStatus: (item.businessStatus as FusedEstimate["businessStatus"]) ?? null,
      });
    }

    // Step 1b: Refresh isOpen/hoursToday for cached estimates using current time
    // (cached fused estimates store a point-in-time snapshot that can go stale)
    const cachedVenueIds = [...nearbyFused.keys()];
    if (cachedVenueIds.length > 0) {
      const googleDataMap = await batchGetItems(cachedVenueIds, "GDATA#CURRENT");
      for (const [venueId, googleData] of googleDataMap) {
        const existing = nearbyFused.get(venueId);
        if (!existing) continue;
        const cachedHours: CachedGoogleHours = {
          businessStatus: (googleData.businessStatus as CachedGoogleHours["businessStatus"]) ?? null,
          regularPeriods: (googleData.regularPeriods as GoogleOpenPeriod[]) ?? [],
          cachedAt: googleData.cachedAt as string,
        };
        const openStatus = isOpenNow(cachedHours, nowMs, timezone);
        existing.isOpen = openStatus.isOpen;
        existing.hoursToday = openStatus.hoursToday;
        existing.businessStatus = cachedHours.businessStatus;
      }
    }

    // Step 2: Fast inline path for warm venues (have cached Foursquare raw data)
    const missing = clientVenues.filter((v) => !nearbyFused.has(v.venueId));
    let inlineCount = 0;
    let coldCount = 0;

    if (missing.length > 0) {
      const missingIds = missing.map((v) => v.venueId);

      // Batch-read FSQDATA#CURRENT and GDATA#CURRENT for all missing venues
      const [fsqDataMap, googleDataMap] = await Promise.all([
        batchGetItems(missingIds, "FSQDATA#CURRENT"),
        batchGetItems(missingIds, "GDATA#CURRENT"),
      ]);

      // Compute scores inline for warm venues (pure math, no DynamoDB writes)
      for (const v of missing) {
        const fsqData = fsqDataMap.get(v.venueId);
        if (fsqData) {
          const data = {
            popularity: (fsqData.popularity as number | null) ?? null,
            rating: (fsqData.rating as number | null) ?? null,
            hoursPopular: (fsqData.hoursPopular as Array<{ day: number; open: string; close: string }>) ?? [],
          };

          // Check Google hours for open/closed status
          const googleData = googleDataMap.get(v.venueId);
          let openStatus: { isOpen: boolean; hoursToday: string | null } | null = null;
          if (googleData) {
            const cachedHours: CachedGoogleHours = {
              businessStatus: (googleData.businessStatus as CachedGoogleHours["businessStatus"]) ?? null,
              regularPeriods: (googleData.regularPeriods as GoogleOpenPeriod[]) ?? [],
              cachedAt: googleData.cachedAt as string,
            };
            openStatus = isOpenNow(cachedHours, nowMs, timezone);
          }

          const { score, confidence } = computeTimeAwareBusyness(data, nowMs, timezone, openStatus?.isOpen);
          nearbyFused.set(v.venueId, {
            venueId: v.venueId,
            busynessScore: Math.round(score * 1000) / 1000,
            confidence: foursquareConfidenceLevel(confidence),
            reportCount: 0,
            waitMinutes: null,
            sourceCount: 1,
            sources: ["foursquare"],
            conflictDetected: false,
            computedAt: new Date(nowMs).toISOString(),
            isOpen: openStatus?.isOpen ?? null,
            hoursToday: openStatus?.hoursToday ?? null,
            businessStatus: googleData ? (googleData.businessStatus as FusedEstimate["businessStatus"]) ?? null : null,
          });
          inlineCount++;
        }
      }

      // Cold venues: no FSQDATA cached at all
      const coldVenues = missing.filter((v) => !fsqDataMap.has(v.venueId));
      coldCount = coldVenues.length;

      // Dispatch ALL missing venues to background for full computation + cache writes
      if (BACKGROUND_FUNCTION) {
        try {
          await lambdaClient.send(
            new InvokeCommand({
              FunctionName: BACKGROUND_FUNCTION,
              InvocationType: "Event",
              Payload: Buffer.from(
                JSON.stringify({
                  venues: missing,
                  timezone,
                  centerLat: lat,
                  centerLng: lng,
                  radius,
                })
              ),
            })
          );
        } catch (err) {
          log.error("Failed to dispatch missing venues", { count: missing.length }, err);
        }
      }

      // For cold venues, use area-average score instead of generic 0.5
      // This gives meaningful colors based on surrounding venues with real data
      if (coldVenues.length > 0) {
        const realEstimates = Array.from(nearbyFused.values()).filter(
          (e) => e.sourceCount > 0
        );
        const areaAvgScore =
          realEstimates.length > 0
            ? realEstimates.reduce((sum, e) => sum + e.busynessScore, 0) / realEstimates.length
            : 0.5;

        log.debug("Cold venues using area-average score", {
          coldCount: coldVenues.length,
          areaAvgScore: Math.round(areaAvgScore * 1000) / 1000,
          realEstimateCount: realEstimates.length,
        });

        for (const v of coldVenues) {
          nearbyFused.set(v.venueId, {
            ...emptyEstimate(v.venueId),
            busynessScore: Math.round(areaAvgScore * 1000) / 1000,
          });
        }
      }
    }

    // Step 3: Return results immediately
    const venues = Array.from(nearbyFused.values());

    done({
      venueCount: venues.length,
      cached: venues.length - missing.length,
      inlineComputed: inlineCount,
      dispatched: missing.length,
      cold: coldCount,
    });
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
      clientVenues = [];
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
