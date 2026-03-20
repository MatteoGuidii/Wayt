import {
  venueKey,
  mappingSK,
  signalSK,
  getItem,
  putItem,
} from "../db";
import { VenueSignal, SOURCE_CONFIG, normalizeLevel } from "./types";

const FOURSQUARE_API_KEY = process.env.FOURSQUARE_API_KEY ?? "";
const FSQ_BASE = "https://api.foursquare.com/v3";
const MAPPING_TTL_DAYS = 30;

interface FsqMatchResponse {
  place?: {
    fsq_id: string;
    name: string;
    popularity?: number;
    stats?: { total_photos?: number; total_tips?: number; total_ratings?: number };
  };
}

interface FsqPlaceDetails {
  fsq_id: string;
  name: string;
  popularity?: number;
  rating?: number;
  stats?: { total_photos?: number; total_tips?: number; total_ratings?: number };
  hours_popular?: Array<{ day: number; open: string; close: string }>;
}

/**
 * Fetch a Foursquare-based busyness signal for a venue.
 * Returns null if the API key is missing, the venue can't be matched, or the request fails.
 */
export async function fetchFoursquareSignal(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number
): Promise<VenueSignal | null> {
  if (!FOURSQUARE_API_KEY) return null;

  try {
    // Step 1: Check for cached venue mapping
    const fsqId = await getCachedMapping(venueId) ?? await matchVenue(venueId, venueName, lat, lng);
    if (!fsqId) return null;

    // Step 2: Fetch place details for popularity data
    const details = await fetchPlaceDetails(fsqId);
    if (!details) return null;

    // Step 3: Compute busyness score from popularity
    const busynessScore = computeBusynessScore(details);
    const config = SOURCE_CONFIG.foursquare;
    const now = Date.now();

    // Step 4: Cache the signal
    const signal: VenueSignal = {
      sourceId: "foursquare",
      venueId,
      busynessScore,
      confidence: details.popularity != null ? 0.7 : 0.4,
      baseWeight: config.weight,
      timestamp: now,
      ttlSeconds: config.ttlSeconds,
    };

    await putItem({
      PK: venueKey(venueId),
      SK: signalSK("foursquare", now),
      ...signal,
      ttl: Math.floor(now / 1000) + config.ttlSeconds,
    });

    return signal;
  } catch (err) {
    console.error("[foursquare] Failed to fetch signal:", err);
    return null;
  }
}

// -----------------------------------------------
// Internal helpers
// -----------------------------------------------

/** Check for a cached Foursquare venue ID mapping. */
async function getCachedMapping(venueId: string): Promise<string | null> {
  const item = await getItem(venueKey(venueId), mappingSK("foursquare"));
  if (!item) return null;

  // Check if mapping has expired
  const ttl = item.ttl as number | undefined;
  if (ttl && ttl < Math.floor(Date.now() / 1000)) return null;

  return (item.fsqId as string) ?? null;
}

/** Match a venue name + coordinates to a Foursquare place ID. */
async function matchVenue(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number
): Promise<string | null> {
  const params = new URLSearchParams({
    name: venueName,
    ll: `${lat},${lng}`,
  });

  const response = await fetch(`${FSQ_BASE}/places/match?${params}`, {
    headers: {
      Authorization: FOURSQUARE_API_KEY,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    console.warn(`[foursquare] Match API returned ${response.status} for "${venueName}"`);
    return null;
  }

  const data = (await response.json()) as FsqMatchResponse;
  const fsqId = data.place?.fsq_id;
  if (!fsqId) return null;

  // Cache the mapping for 30 days
  const now = Math.floor(Date.now() / 1000);
  await putItem({
    PK: venueKey(venueId),
    SK: mappingSK("foursquare"),
    fsqId,
    fsqName: data.place?.name,
    cachedAt: new Date().toISOString(),
    ttl: now + MAPPING_TTL_DAYS * 86_400,
  });

  return fsqId;
}

/** Fetch Foursquare place details including popularity. */
async function fetchPlaceDetails(fsqId: string): Promise<FsqPlaceDetails | null> {
  const fields = "fsq_id,name,popularity,rating,stats,hours_popular";
  const response = await fetch(`${FSQ_BASE}/places/${fsqId}?fields=${fields}`, {
    headers: {
      Authorization: FOURSQUARE_API_KEY,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    console.warn(`[foursquare] Details API returned ${response.status} for fsq_id=${fsqId}`);
    return null;
  }

  return (await response.json()) as FsqPlaceDetails;
}

/**
 * Compute a 0.0-1.0 busyness score from Foursquare place data.
 *
 * Primary signal: `popularity` (0.0-1.0) — directly usable.
 * Fallback: derive from rating and stats as a rough proxy.
 */
function computeBusynessScore(details: FsqPlaceDetails): number {
  // Direct popularity field — best signal
  if (details.popularity != null) {
    return Math.max(0, Math.min(1, details.popularity));
  }

  // Fallback: use rating as a rough proxy
  // Higher-rated places tend to be busier (correlation, not causation)
  if (details.rating != null) {
    // Foursquare rating is 0-10; normalize to 0-1 with moderate baseline
    return Math.max(0.2, Math.min(0.8, details.rating / 10));
  }

  // Last resort: moderate baseline
  return 0.5;
}
