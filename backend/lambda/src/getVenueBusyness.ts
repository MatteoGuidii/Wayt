import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { venueKey, fusedSK, getItem, queryByPK } from "./db";
import { success, badRequest, serverError } from "./shared";
import { computeVenueBusyness } from "./computeVenueBusyness";
import { FusedEstimate, SignalSource } from "./signals/types";
import { createLogger } from "./logger";

/**
 * GET /v1/venues/{venueId}/busyness?venueName=&lat=&lng=
 *
 * Returns a detailed fused busyness estimate for a single venue,
 * including signal breakdown.
 */
export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getVenueBusyness", event, context);
  const done = log.startTimer("Handler complete");
  try {
    const venueId = decodeURIComponent(event.pathParameters?.venueId ?? "");
    if (!venueId) {
      return badRequest("Missing venueId path parameter");
    }

    log.info("Fetching venue busyness", { venueId });

    const params = event.queryStringParameters ?? {};
    const venueName = params.venueName ?? "";
    const lat = parseFloat(params.lat ?? "");
    const lng = parseFloat(params.lng ?? "");

    const timezone = params.timezone ?? "UTC";

    if (!venueName || isNaN(lat) || isNaN(lng)) {
      return badRequest("Missing required query parameters: venueName, lat, lng");
    }

    // Step 1: Check for cached fused estimate
    const nowSeconds = Math.floor(Date.now() / 1000);
    let fused: FusedEstimate | null = null;

    const cached = await getItem(venueKey(venueId), fusedSK());
    if (cached) {
      const ttl = cached.ttl as number | undefined;
      if (!ttl || ttl >= nowSeconds) {
        fused = {
          venueId: cached.venueId as string,
          busynessScore: cached.busynessScore as number,
          confidence: cached.confidence as FusedEstimate["confidence"],
          reportCount: cached.reportCount as number,
          waitMinutes: (cached.waitMinutes as number | null) ?? null,
          sourceCount: cached.sourceCount as number,
          sources: cached.sources as string[],
          conflictDetected: cached.conflictDetected as boolean,
          computedAt: cached.computedAt as string,
        };
      }
    }

    // Step 2: If no valid cache, compute fresh
    if (!fused) {
      log.debug("Cache miss, computing fresh", { venueId });
      fused = await computeVenueBusyness({ venueId, venueName, lat, lng, timezone });
    } else {
      log.debug("Cache hit", { venueId });
    }

    // Step 3: Build signal breakdown from cache
    const signalItems = await queryByPK(venueKey(venueId), "SIGNAL#");
    const signals = signalItems
      .filter((item) => {
        const ttl = item.ttl as number | undefined;
        return !ttl || ttl >= nowSeconds;
      })
      .map((item) => {
        const ts = item.timestamp as number;
        return {
          source: item.sourceId as string,
          score: item.busynessScore as number,
          confidence: item.confidence as number,
          ageMinutes: Math.round((Date.now() - ts) / 60_000),
        };
      });

    done({ venueId, score: fused.busynessScore, confidence: fused.confidence, sourceCount: fused.sourceCount });
    return success({
      ...fused,
      signals,
    });
  } catch (err) {
    log.error("Failed to fetch venue busyness", undefined, err);
    return serverError("Failed to fetch venue busyness");
  }
}
