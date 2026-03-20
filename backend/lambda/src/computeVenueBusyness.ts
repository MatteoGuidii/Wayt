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

/** TTL for the cached fused estimate (10 minutes). */
const FUSED_TTL_SECONDS = 10 * 60;

export interface ComputeInput {
  venueId: string;
  venueName: string;
  lat: number;
  lng: number;
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
  const { venueId, venueName, lat, lng } = input;
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);

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
        fetchSignalBySource(sourceId, venueId, venueName, lat, lng)
      );
      const results = await Promise.all(fetches);

      for (const signal of results) {
        if (signal) {
          freshSignals.push(signal);
        }
      }
    }

    // Step 3: Fuse all available signals
    const fused = freshSignals.length > 0
      ? fuseSignals(freshSignals, now)
      : emptyEstimate(venueId);

    // Step 4: Cache the fused result with geohash for spatial queries
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

    return fused;
  } catch (err) {
    console.error("[computeVenueBusyness] Error:", err);
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
  lng: number
): Promise<VenueSignal | null> {
  switch (sourceId) {
    case "foursquare":
      return fetchFoursquareSignal(venueId, venueName, lat, lng);
    case "user_reports":
      return aggregateUserReports(venueId);
    default:
      return null;
  }
}
