import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { venueKey, fusedSK, getItem, queryByPK, mappingSK } from "./db";
import { success, badRequest, serverError } from "./shared";
import { computeVenueBusyness } from "./computeVenueBusyness";
import { FusedEstimate, VenueDetailsFull } from "./signals/types";
import { getGoogleHoursData, isOpenNow, getGoogleVenueDetails, ensureVenueDetails } from "./signals/google";
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
    const address = params.address || undefined;

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
          isOpen: (cached.isOpen as boolean | null) ?? null,
          hoursToday: (cached.hoursToday as string | null) ?? null,
          businessStatus: (cached.businessStatus as FusedEstimate["businessStatus"]) ?? null,
        };
      }
    }

    // Step 2: If no valid cache, compute fresh
    if (!fused) {
      log.debug("Cache miss, computing fresh", { venueId });
      fused = await computeVenueBusyness({ venueId, venueName, lat, lng, timezone, address });
    } else {
      log.debug("Cache hit", { venueId });

      // If cached estimate is missing Google hours, try to resolve them now.
      // This catches venues where Google matching failed during batch processing
      // (circuit breaker, timeout) but succeeds on a direct single-venue request.
      if (fused.isOpen == null) {
        const googleResult = await getGoogleHoursData(venueId, venueName, lat, lng, address);
        if (googleResult) {
          const openStatus = isOpenNow(googleResult.hours, Date.now(), timezone);
          fused.isOpen = openStatus.isOpen;
          fused.hoursToday = openStatus.hoursToday;
          fused.businessStatus = googleResult.hours.businessStatus;
          log.debug("Backfilled Google hours for cached estimate", { venueId, isOpen: fused.isOpen });
        }
      }
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

    // Fetch full venue details (including reviews) for single-venue response.
    // If not cached, try to resolve via Google API (handles venues where
    // batch processing skipped details due to circuit breaker / timeout).
    let cachedDetails = await getGoogleVenueDetails(venueId);
    if (!cachedDetails) {
      cachedDetails = await ensureVenueDetails(venueId);
    }
    // Build Google Maps URL using Place ID for exact venue (handles chains)
    const mapping = await getItem(venueKey(venueId), mappingSK("google"));
    const placeId = mapping?.googlePlaceId as string | undefined;
    const googleMapsUrl = placeId && placeId !== "__NO_MATCH__"
      ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(venueName ?? "")}&query_place_id=${placeId}`
      : null;

    const venueDetails: VenueDetailsFull | null = cachedDetails ? {
      primaryType: cachedDetails.primaryType,
      primaryTypeDisplayName: cachedDetails.primaryTypeDisplayName,
      rating: cachedDetails.rating,
      userRatingCount: cachedDetails.userRatingCount,
      priceLevel: cachedDetails.priceLevel,
      priceRange: cachedDetails.priceRange,
      types: cachedDetails.types,
      reviews: cachedDetails.reviews,
      editorialSummary: cachedDetails.editorialSummary,
      googleMapsUrl,
    } : null;

    done({ venueId, score: fused.busynessScore, confidence: fused.confidence, sourceCount: fused.sourceCount });
    return success({
      ...fused,
      venueDetails,
      signals,
    });
  } catch (err) {
    log.error("Failed to fetch venue busyness", undefined, err);
    return serverError("Failed to fetch venue busyness");
  }
}
