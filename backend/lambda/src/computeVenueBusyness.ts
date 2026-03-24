import {
  venueKey,
  fusedSK,
  queryByPK,
  putItem,
} from "./db";
import { encode } from "./geohash";
import { VenueSignal, FusedEstimate, SOURCE_CONFIG, SignalSource } from "./signals/types";
import { fuseSignals, emptyEstimate } from "./signals/fusion";
import { fetchFoursquareSignal } from "./signals/foursquare";
import { aggregateUserReports } from "./signals/userReports";
import { getGoogleHoursData, isOpenNow } from "./signals/google";
import { createLogger } from "./logger";

/** TTL for the cached fused estimate (2 hours).
 * The Gaussian temporal model changes slowly (~hour-wide peaks),
 * so 2-hour recomputation frequency is sufficient. Longer TTL means
 * app reopens within 2 hours hit the fast geohash cache path. */
const FUSED_TTL_SECONDS = 2 * 60 * 60;

export interface ComputeInput {
  venueId: string;
  venueName: string;
  lat: number;
  lng: number;
  timezone?: string;
}

/**
 * Compute (or retrieve cached) fused busyness estimate for a single venue.
 *
 * 1. Check signal cache for unexpired signals
 * 2. For each missing/expired source, fetch fresh signals in parallel
 * 3. Write fresh signals to cache
 * 4. Run fusion algorithm
 * 5. Cache and return the fused result
 */
export async function computeVenueBusyness(input: ComputeInput): Promise<FusedEstimate> {
  const { venueId, venueName, lat, lng, timezone } = input;
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);

  const log = createLogger("computeVenueBusyness");

  try {
    // Step 1: Check for cached signals
    const cachedItems = await queryByPK(venueKey(venueId), "SIGNAL#");
    const cachedSignals = parseCachedSignals(cachedItems, now);

    // Determine which sources need refreshing
    const freshSources = new Set(cachedSignals.map((s) => s.sourceId));
    const staleSourceIds: SignalSource[] = [];

    for (const sourceId of Object.keys(SOURCE_CONFIG) as SignalSource[]) {
      if (!freshSources.has(sourceId)) {
        staleSourceIds.push(sourceId);
      }
    }

    // Step 2: Fetch missing/expired signals in parallel
    const freshSignals: VenueSignal[] = [...cachedSignals];

    if (staleSourceIds.length > 0) {
      const fetches = staleSourceIds.map((sourceId) =>
        fetchSignalBySource(sourceId, venueId, venueName, lat, lng, timezone)
      );
      const results = await Promise.all(fetches);

      for (const signal of results) {
        if (signal) {
          freshSignals.push(signal);
        }
      }
    }

    log.debug("Signal status", { venueId, cached: cachedSignals.length, stale: staleSourceIds });

    // Step 2b: Fetch Google hours for open/closed status (parallel with signals)
    const googleHours = await getGoogleHoursData(venueId, venueName, lat, lng);
    const openStatus = googleHours ? isOpenNow(googleHours, now, timezone ?? "UTC") : null;

    // Step 3: Fuse all available signals
    const fused = freshSignals.length > 0
      ? fuseSignals(freshSignals, now)
      : emptyEstimate(venueId);

    // Attach Google hours data to the fused estimate
    fused.isOpen = openStatus?.isOpen ?? null;
    fused.hoursToday = openStatus?.hoursToday ?? null;
    fused.businessStatus = googleHours?.businessStatus ?? null;

    // When venue is closed, override busyness to zero
    if (openStatus?.isOpen === false) {
      fused.busynessScore = 0.0;
    }

    log.info("Fused estimate computed", { venueId, score: fused.busynessScore, confidence: fused.confidence, sources: fused.sources, isOpen: fused.isOpen });

    // Step 5: Cache the fused result with geohash for spatial queries.
    // Only cache if we have real signals — don't persist empty estimates
    // (no Foursquare match + no user reports) so the system retries next time.
    if (freshSignals.length > 0) {
      const geohash = encode(lat, lng);
      await putItem({
        PK: venueKey(venueId),
        SK: fusedSK(),
        geohash,
        geoSK: `FUSED#${venueId}`,
        ...fused,
        lat,
        lng,
        venueName,
        ttl: nowSeconds + FUSED_TTL_SECONDS,
      });
    }

    return fused;
  } catch (err) {
    log.error("Computation failed", { venueId }, err);
    return emptyEstimate(venueId);
  }
}

// -----------------------------------------------
// Helpers
// -----------------------------------------------

/** Parse cached signal items, filtering out expired ones. */
function parseCachedSignals(
  items: Record<string, unknown>[],
  now: number
): VenueSignal[] {
  const nowSeconds = Math.floor(now / 1000);
  const signals: VenueSignal[] = [];

  for (const item of items) {
    const ttl = item.ttl as number | undefined;
    if (ttl && ttl < nowSeconds) continue; // expired

    const signal: VenueSignal = {
      sourceId: item.sourceId as SignalSource,
      venueId: item.venueId as string,
      busynessScore: item.busynessScore as number,
      confidence: item.confidence as number,
      baseWeight: item.baseWeight as number,
      timestamp: item.timestamp as number,
      ttlSeconds: item.ttlSeconds as number,
      reportCount: item.reportCount as number | undefined,
      waitMinutes: item.waitMinutes as number | undefined,
    };

    signals.push(signal);
  }

  // Deduplicate: keep only the freshest signal per source
  const bySource = new Map<string, VenueSignal>();
  for (const s of signals) {
    const existing = bySource.get(s.sourceId);
    if (!existing || s.timestamp > existing.timestamp) {
      bySource.set(s.sourceId, s);
    }
  }

  return Array.from(bySource.values());
}

/** Dispatch signal fetch by source ID. */
async function fetchSignalBySource(
  sourceId: SignalSource,
  venueId: string,
  venueName: string,
  lat: number,
  lng: number,
  timezone?: string
): Promise<VenueSignal | null> {
  switch (sourceId) {
    case "foursquare":
      return fetchFoursquareSignal(venueId, venueName, lat, lng, timezone);
    case "user_reports":
      return aggregateUserReports(venueId);
    default:
      return null;
  }
}
