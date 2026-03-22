import { computeVenueBusyness, ComputeInput } from "./computeVenueBusyness";
import { batchCheckExists } from "./db";
import { createLogger } from "./logger";

/**
 * Async background Lambda invoked by getNearbyVenues for ALL missing venues.
 *
 * Two-phase processing:
 * 1. **Warm venues** (have cached Foursquare raw data): processed first with
 *    high concurrency (20) — no external API calls, just DynamoDB reads + score math.
 * 2. **Cold venues** (need Foursquare API): processed second with low concurrency (5)
 *    to avoid rate limiting.
 *
 * Results are written to DynamoDB and picked up by the iOS app on its
 * follow-up refresh (~5 seconds after initial load).
 */

interface BackgroundEvent {
  venues: ComputeInput[];
  timezone: string;
}

/** High concurrency for warm venues (no external API calls). */
const WARM_CONCURRENCY = 20;
/** High concurrency for cold venues — Foursquare allows 50 QPS. */
const COLD_CONCURRENCY = 40;

export async function handler(event: BackgroundEvent): Promise<void> {
  const log = createLogger("computeBackground");
  const { venues, timezone } = event;

  if (!venues || venues.length === 0) {
    log.info("No venues to process");
    return;
  }

  // Classify warm vs cold
  const venueIds = venues.map((v) => v.venueId);
  const warmIds = await batchCheckExists(venueIds, "FSQDATA#CURRENT");

  const warmVenues: ComputeInput[] = [];
  const coldVenues: ComputeInput[] = [];

  for (const v of venues) {
    if (warmIds.has(v.venueId)) {
      warmVenues.push(v);
    } else {
      coldVenues.push(v);
    }
  }

  log.info("Background compute starting", {
    total: venues.length,
    warm: warmVenues.length,
    cold: coldVenues.length,
  });

  // Phase 1: Warm venues first (fast — high concurrency)
  let warmProcessed = 0;
  if (warmVenues.length > 0) {
    warmProcessed = await processPool(warmVenues, timezone, WARM_CONCURRENCY, log);
    log.info("Warm phase complete", { processed: warmProcessed, total: warmVenues.length });
  }

  // Phase 2: Cold venues (slow — low concurrency to avoid Foursquare rate limits)
  let coldProcessed = 0;
  if (coldVenues.length > 0) {
    coldProcessed = await processPool(coldVenues, timezone, COLD_CONCURRENCY, log);
    log.info("Cold phase complete", { processed: coldProcessed, total: coldVenues.length });
  }

  log.info("Background compute done", {
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
