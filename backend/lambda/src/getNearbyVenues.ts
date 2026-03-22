import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { LambdaClient, InvokeCommand } from "@aws-sdk/client-lambda";
import { queryNearbyFused, batchCheckExists } from "./db";
import { haversineDistance, success, badRequest, serverError } from "./shared";
import { FusedEstimate } from "./signals/types";
import { computeVenueBusyness, ComputeInput } from "./computeVenueBusyness";
import { emptyEstimate } from "./signals/fusion";
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
 * Ultra-fast path: returns ONLY cached fused estimates from DynamoDB.
 * Any venues not in cache are dispatched to a background Lambda for
 * async computation — results appear on the next client refresh.
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

    const nowSeconds = Math.floor(Date.now() / 1000);
    const nearbyFused = new Map<string, FusedEstimate>();

    for (const item of cachedItems) {
      const itemLat = item.lat as number;
      const itemLng = item.lng as number;
      const ttl = item.ttl as number | undefined;

      if (ttl && ttl < nowSeconds) continue;

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
        hoursToday: (item.hoursToday as FusedEstimate["hoursToday"]) ?? [],
      });
    }

    // Step 2: Classify missing venues as warm (cached FSQ data) vs cold (need API)
    const missing = clientVenues.filter((v) => !nearbyFused.has(v.venueId));
    let warmCount = 0;
    let coldCount = 0;

    if (missing.length > 0) {
      const missingIds = missing.map((v) => v.venueId);
      const warmIds = await batchCheckExists(missingIds, "FSQDATA#CURRENT");

      const warmVenues = missing.filter((v) => warmIds.has(v.venueId));
      const coldVenues = missing.filter((v) => !warmIds.has(v.venueId));
      warmCount = warmVenues.length;
      coldCount = coldVenues.length;

      log.info("Missing venues classified", { warm: warmCount, cold: coldCount });

      // Compute warm venues inline (DynamoDB-only, no Foursquare API calls)
      if (warmVenues.length > 0) {
        const warmResults = await Promise.all(
          warmVenues.map((v) => computeVenueBusyness({ ...v, timezone }))
        );
        for (const result of warmResults) {
          nearbyFused.set(result.venueId, result);
        }
      }

      // Dispatch ONLY cold venues to background Lambda
      if (coldVenues.length > 0 && BACKGROUND_FUNCTION) {
        try {
          await lambdaClient.send(
            new InvokeCommand({
              FunctionName: BACKGROUND_FUNCTION,
              InvocationType: "Event",
              Payload: Buffer.from(
                JSON.stringify({ venues: coldVenues, timezone })
              ),
            })
          );
        } catch (err) {
          log.warn("Failed to dispatch cold venues", { count: coldCount });
        }
      }

      // Empty estimates for cold venues only
      for (const v of coldVenues) {
        nearbyFused.set(v.venueId, emptyEstimate(v.venueId));
      }
    }

    // Step 3: Return results immediately
    const venues = Array.from(nearbyFused.values());

    done({
      venueCount: venues.length,
      cached: venues.length - warmCount - coldCount,
      inlineComputed: warmCount,
      dispatched: coldCount,
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
