import { computeVenueBusyness, ComputeInput } from "./computeVenueBusyness";
import { batchCheckExists, batchPutItems, venueKey, fusedSK } from "./db";
import { encode } from "./geohash";
import { createLogger } from "./logger";
import {
  batchMatchVenues,
  computeTimeAwareBusyness,
} from "./signals/foursquare";
import { getGoogleHoursData, isOpenNow } from "./signals/google";
import { foursquareConfidenceLevel } from "./signals/fusion";

/**
 * Async background Lambda invoked by getNearbyVenues for ALL missing venues.
 *
 * Three-phase processing:
 * 1. **Batch search**: Single Foursquare area search (1-3 API calls) to match
 *    cold venues and write quick fused estimates immediately.
 * 2. **Warm venues** (have cached Foursquare raw data): processed with high
 *    concurrency — no external API calls, just DynamoDB reads + score math.
 * 3. **Remaining cold venues** (no match from batch search): processed with
 *    individual Foursquare API calls as a fallback.
 *
 * Results are written to DynamoDB and picked up by the iOS app on its
 * follow-up refresh (~2 seconds after initial load).
 */

interface BackgroundEvent {
  venues: ComputeInput[];
  timezone: string;
  centerLat?: number;
  centerLng?: number;
  radius?: number;
}

/** TTL for quick fused estimates (2 hours, same as full computation). */
const QUICK_ESTIMATE_TTL_SECONDS = 2 * 60 * 60;

/** High concurrency for warm venues (no external API calls). */
const WARM_CONCURRENCY = 20;
/** Concurrency for remaining cold venues — individual Foursquare API calls.
 *  Kept at 15 to avoid Foursquare 429 rate limit cascades with exponential backoff. */
const COLD_CONCURRENCY = 15;

export async function handler(event: BackgroundEvent): Promise<void> {
  const log = createLogger("computeBackground");
  const { venues, timezone, centerLat, centerLng, radius } = event;

  if (!venues || venues.length === 0) {
    log.info("No venues to process");
    return;
  }

  // Phase 0: Classify initial warm vs cold
  const venueIds = venues.map((v) => v.venueId);
  const warmIds = await batchCheckExists(venueIds, "FSQDATA#CURRENT");

  let warmVenues = venues.filter((v) => warmIds.has(v.venueId));
  let coldVenues = venues.filter((v) => !warmIds.has(v.venueId));
  const coldVenueMap = new Map(coldVenues.map((v) => [v.venueId, v]));

  log.info("Initial classification", {
    total: venues.length,
    warm: warmVenues.length,
    cold: coldVenues.length,
  });

  // Phase 1: Batch Foursquare area search for cold venues
  // Replaces N individual matchVenue() calls with 1-3 area searches
  let batchMatched = 0;
  if (coldVenues.length > 0) {
    const batchLat = centerLat ?? averageCoord(coldVenues, "lat");
    const batchLng = centerLng ?? averageCoord(coldVenues, "lng");
    const batchRadius = radius ?? 2000;

    const matched = await batchMatchVenues(coldVenues, batchLat, batchLng, batchRadius);
    batchMatched = matched.size;

    if (matched.size > 0) {
      // Write quick fused estimates for all batch-matched venues immediately
      const nowMs = Date.now();
      const nowSeconds = Math.floor(nowMs / 1000);
      const quickEstimates: Record<string, unknown>[] = [];

      // Fetch Google hours for matched venues (5 concurrent max)
      const matchedEntries = Array.from(matched.entries());
      const googleHoursMap = new Map<string, { isOpen: boolean; hoursToday: string | null; businessStatus: string | null }>();
      const GOOGLE_CONCURRENCY = 5;

      for (let i = 0; i < matchedEntries.length; i += GOOGLE_CONCURRENCY) {
        const batch = matchedEntries.slice(i, i + GOOGLE_CONCURRENCY);
        const results = await Promise.all(
          batch.map(async ([venueId]) => {
            const venue = coldVenueMap.get(venueId);
            if (!venue) return null;
            const hours = await getGoogleHoursData(venueId, venue.venueName, venue.lat, venue.lng);
            if (!hours) return null;
            const status = isOpenNow(hours, nowMs, timezone);
            return { venueId, ...status, businessStatus: hours.businessStatus ?? null };
          })
        );
        for (const r of results) {
          if (r) googleHoursMap.set(r.venueId, { isOpen: r.isOpen, hoursToday: r.hoursToday, businessStatus: r.businessStatus });
        }
      }

      for (const [venueId, match] of matched) {
        const openStatus = googleHoursMap.get(venueId) ?? null;
        const { score, confidence } = computeTimeAwareBusyness(match.data, nowMs, timezone, openStatus?.isOpen);
        const venue = coldVenueMap.get(venueId);
        const lat = venue?.lat ?? 0;
        const lng = venue?.lng ?? 0;
        const geohash = encode(lat, lng);

        quickEstimates.push({
          PK: venueKey(venueId),
          SK: fusedSK(),
          geohash,
          geoSK: `FUSED#${venueId}`,
          venueId,
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
          businessStatus: openStatus?.businessStatus ?? null,
          lat,
          lng,
          venueName: venue?.venueName ?? "",
          ttl: nowSeconds + QUICK_ESTIMATE_TTL_SECONDS,
        });
      }

      await batchPutItems(quickEstimates);
      log.info("Quick estimates written", { count: quickEstimates.length });

      // Batch-matched cold venues are now warm (have FSQDATA#CURRENT cached)
      const matchedIds = new Set(matched.keys());
      const nowWarm = coldVenues.filter((v) => matchedIds.has(v.venueId));
      const stillCold = coldVenues.filter((v) => !matchedIds.has(v.venueId));

      warmVenues = [...warmVenues, ...nowWarm];
      coldVenues = stillCold;
    }

    log.info("Batch search complete", {
      matched: batchMatched,
      stillCold: coldVenues.length,
      totalWarm: warmVenues.length,
    });
  }

  // Phase 2: Process warm venues (full computation with cached FSQ data)
  let warmProcessed = 0;
  if (warmVenues.length > 0) {
    warmProcessed = await processPool(warmVenues, timezone, WARM_CONCURRENCY, log);
    log.info("Warm phase complete", { processed: warmProcessed, total: warmVenues.length });
  }

  // Phase 3: Remaining cold venues — individual Foursquare API calls as fallback
  let coldProcessed = 0;
  if (coldVenues.length > 0) {
    coldProcessed = await processPool(coldVenues, timezone, COLD_CONCURRENCY, log);
    log.info("Cold phase complete", { processed: coldProcessed, total: coldVenues.length });
  }

  log.info("Background compute done", {
    batchMatched,
    warmProcessed,
    coldProcessed,
    total: venues.length,
  });
}

async function processPool(
  venues: ComputeInput[],
  timezone: string,
  concurrency: number,
  log: ReturnType<typeof createLogger>
): Promise<number> {
  const queue = [...venues];
  let processed = 0;

  const workers = Array.from({ length: Math.min(concurrency, queue.length) }, async () => {
    while (queue.length > 0) {
      const venue = queue.shift();
      if (!venue) break;

      try {
        await computeVenueBusyness({ ...venue, timezone });
        processed++;
      } catch {
        log.warn("Failed to compute venue", { venueId: venue.venueId });
      }
    }
  });

  await Promise.all(workers);
  return processed;
}

/** Compute the average of a coordinate field across venues. */
function averageCoord(venues: ComputeInput[], field: "lat" | "lng"): number {
  if (venues.length === 0) return 0;
  return venues.reduce((sum, v) => sum + v[field], 0) / venues.length;
}
