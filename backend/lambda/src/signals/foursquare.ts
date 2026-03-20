import {
  venueKey,
  mappingSK,
  signalSK,
  getItem,
  putItem,
} from "../db";
import { VenueSignal, SOURCE_CONFIG } from "./types";

const FOURSQUARE_API_KEY = process.env.FOURSQUARE_API_KEY ?? "";
const FSQ_BASE = "https://places-api.foursquare.com";
const FSQ_API_VERSION = "2025-06-17";
const MAPPING_TTL_DAYS = 30;
const DATA_TTL_DAYS = 30;

const FSQ_HEADERS = {
  Authorization: `Bearer ${FOURSQUARE_API_KEY}`,
  Accept: "application/json",
  "X-Places-Api-Version": FSQ_API_VERSION,
};

interface FsqSearchResponse {
  results?: Array<{
    fsq_place_id: string;
    name: string;
    popularity?: number;
    rating?: number;
    distance?: number;
    stats?: { total_photos?: number; total_tips?: number; total_ratings?: number };
  }>;
}

interface FsqPlaceDetails {
  fsq_place_id: string;
  name: string;
  popularity?: number;
  rating?: number;
  stats?: { total_photos?: number; total_tips?: number; total_ratings?: number };
  hours_popular?: Array<{ day: number; open: string; close: string }>;
}

/** Cached raw Foursquare venue data (popularity + hours_popular). */
interface CachedFsqData {
  popularity: number | null;
  rating: number | null;
  hoursPopular: Array<{ day: number; open: string; close: string }>;
}

/**
 * Produce a Foursquare-based busyness signal for a venue.
 *
 * Raw venue data (popularity, hours_popular) is cached for 30 days to minimize
 * API calls. The time-aware busyness score is recomputed on every call using
 * the cached data + current time, so it stays accurate throughout the day.
 */
export async function fetchFoursquareSignal(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number
): Promise<VenueSignal | null> {
  if (!FOURSQUARE_API_KEY) return null;

  try {
    // Step 1: Get raw Foursquare data (from 30-day cache or fresh API call)
    const data = await getFoursquareVenueData(venueId, venueName, lat, lng);
    if (!data) return null;

    // Step 2: Compute time-aware score from cached data + current time
    const now = Date.now();
    const { score: busynessScore, confidence } = computeTimeAwareBusyness(data, now);
    const config = SOURCE_CONFIG.foursquare;

    const signal: VenueSignal = {
      sourceId: "foursquare",
      venueId,
      busynessScore,
      confidence,
      baseWeight: config.weight,
      timestamp: now,
      ttlSeconds: config.ttlSeconds,
    };

    // Cache the derived signal for 10 min so computeVenueBusyness doesn't
    // re-derive on every request. Score refreshes when this TTL expires,
    // picking up the new time-of-day from the 30-day raw data cache.
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
// Raw data caching (30-day TTL)
// -----------------------------------------------

const FSQDATA_SK = "FSQDATA#CURRENT";

/** Get raw Foursquare venue data, using 30-day DynamoDB cache. */
async function getFoursquareVenueData(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number
): Promise<CachedFsqData | null> {
  // Check cache first
  const cached = await getItem(venueKey(venueId), FSQDATA_SK);
  if (cached) {
    const ttl = cached.ttl as number | undefined;
    if (!ttl || ttl >= Math.floor(Date.now() / 1000)) {
      return {
        popularity: (cached.popularity as number | null) ?? null,
        rating: (cached.rating as number | null) ?? null,
        hoursPopular: (cached.hoursPopular as CachedFsqData["hoursPopular"]) ?? [],
      };
    }
  }

  // Cache miss — fetch from Foursquare API
  const fsqId = await getCachedMapping(venueId) ?? await matchVenue(venueId, venueName, lat, lng);
  if (!fsqId) return null;

  const details = await fetchPlaceDetails(fsqId);
  if (!details) return null;

  const data: CachedFsqData = {
    popularity: details.popularity ?? null,
    rating: details.rating ?? null,
    hoursPopular: details.hours_popular ?? [],
  };

  // Cache raw data for 30 days
  const nowSeconds = Math.floor(Date.now() / 1000);
  await putItem({
    PK: venueKey(venueId),
    SK: FSQDATA_SK,
    ...data,
    cachedAt: new Date().toISOString(),
    ttl: nowSeconds + DATA_TTL_DAYS * 86_400,
  });

  return data;
}

// -----------------------------------------------
// Foursquare API helpers
// -----------------------------------------------

/** Check for a cached Foursquare venue ID mapping. */
async function getCachedMapping(venueId: string): Promise<string | null> {
  const item = await getItem(venueKey(venueId), mappingSK("foursquare"));
  if (!item) return null;

  const ttl = item.ttl as number | undefined;
  if (ttl && ttl < Math.floor(Date.now() / 1000)) return null;

  return (item.fsqId as string) ?? null;
}

/** Search for a venue by name + coordinates and return the best Foursquare place ID. */
async function matchVenue(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number
): Promise<string | null> {
  const params = new URLSearchParams({
    query: venueName,
    ll: `${lat},${lng}`,
    limit: "1",
  });

  const response = await fetch(`${FSQ_BASE}/places/search?${params}`, {
    headers: FSQ_HEADERS,
  });

  if (!response.ok) {
    console.warn(`[foursquare] Search API returned ${response.status} for "${venueName}"`);
    return null;
  }

  const data = (await response.json()) as FsqSearchResponse;
  const topResult = data.results?.[0];
  if (!topResult) return null;

  const fsqId = topResult.fsq_place_id;

  // Cache the mapping for 30 days
  const now = Math.floor(Date.now() / 1000);
  await putItem({
    PK: venueKey(venueId),
    SK: mappingSK("foursquare"),
    fsqId,
    fsqName: topResult.name,
    cachedAt: new Date().toISOString(),
    ttl: now + MAPPING_TTL_DAYS * 86_400,
  });

  return fsqId;
}

/** Fetch Foursquare place details including popularity. */
async function fetchPlaceDetails(fsqId: string): Promise<FsqPlaceDetails | null> {
  const fields = "fsq_place_id,name,popularity,rating,stats,hours_popular";
  const response = await fetch(`${FSQ_BASE}/places/${fsqId}?fields=${fields}`, {
    headers: FSQ_HEADERS,
  });

  if (!response.ok) {
    console.warn(`[foursquare] Details API returned ${response.status} for fsq_id=${fsqId}`);
    return null;
  }

  return (await response.json()) as FsqPlaceDetails;
}

// -----------------------------------------------
// Gaussian temporal busyness model
// -----------------------------------------------

/**
 * Day-of-week amplitude multipliers.
 * Reflects that a Friday dinner peak is more intense than a Tuesday one,
 * even if both have popular windows. Derived from industry foot traffic data.
 * Saturday = 1.0 reference for restaurants; Friday for bars.
 */
const DAY_MULTIPLIERS: Record<number, number> = {
  0: 0.70,  // Sunday
  1: 0.55,  // Monday
  2: 0.60,  // Tuesday
  3: 0.65,  // Wednesday
  4: 0.75,  // Thursday
  5: 0.95,  // Friday
  6: 1.00,  // Saturday (reference)
};

/**
 * Compute a time-aware busyness score using a Sum of Gaussians model.
 *
 * Each popular window becomes a bell curve centered at its midpoint.
 * Busyness at any time = popularity × dayMultiplier × Σ gaussian curves.
 *
 * This produces smooth, continuous transitions: crowds ramp up before peak,
 * hit maximum at center, and taper off naturally. No artificial edge zones.
 *
 * Based on the approach described in "Predicting Temporal Activity Patterns
 * of New Venues" (EPJ Data Science, 2018) and how Google Popular Times works.
 */
function computeTimeAwareBusyness(
  data: CachedFsqData,
  nowMs: number
): { score: number; confidence: number } {
  const basePopularity = data.popularity ?? (data.rating != null ? data.rating / 10 : null);

  if (basePopularity == null) {
    return { score: 0.5, confidence: 0.2 };
  }

  const popularity = Math.max(0, Math.min(1, basePopularity));
  const now = new Date(nowMs);
  const currentDay = now.getUTCDay(); // 0 = Sunday
  const currentMinutes = now.getUTCHours() * 60 + now.getUTCMinutes();

  // Without hours_popular we have no temporal shape — weak baseline only
  if (data.hoursPopular.length === 0) {
    return {
      score: popularity * 0.15,
      confidence: 0.25,
    };
  }

  // Find popular windows for today
  const todayWindows = data.hoursPopular
    .filter((h) => h.day === currentDay)
    .map((h) => ({
      open: parseTimeToMinutes(h.open),
      close: parseTimeToMinutes(h.close),
    }));

  if (todayWindows.length === 0) {
    // No popular hours today — venue is likely quiet
    return {
      score: popularity * 0.05,
      confidence: 0.4,
    };
  }

  // Sum of Gaussians: each window contributes a bell curve
  // sigma = windowDuration / 4 → 95% of the curve falls within the window
  // Minimum sigma of 15 min to avoid infinitely sharp peaks for short windows
  let gaussianSum = 0;
  for (const w of todayWindows) {
    const mu = (w.open + w.close) / 2;
    const sigma = Math.max((w.close - w.open) / 4, 15);
    const diff = currentMinutes - mu;
    gaussianSum += Math.exp(-(diff * diff) / (2 * sigma * sigma));
  }

  // Clamp to [0, 1] — overlapping peaks can sum above 1
  const temporalShape = Math.min(1, gaussianSum);

  // Day-of-week amplitude scaling
  const dayMult = DAY_MULTIPLIERS[currentDay] ?? 0.7;

  // Final score: popularity (capacity) × day multiplier × temporal shape
  // Floor of 0.05 ensures we never predict absolute zero for an open venue
  const score = Math.min(1, popularity * dayMult * (0.05 + 0.95 * temporalShape));

  // Confidence: higher when we're near a known peak or clearly in a trough
  const confidence = computeTemporalConfidence(temporalShape, todayWindows.length);

  return { score, confidence };
}

/**
 * Confidence increases when the temporal model is more certain:
 * - Near a peak (high gaussian) → we know it should be busy → higher confidence
 * - Deep in a trough (low gaussian) → we know it should be quiet → decent confidence
 * - Transitional zone (mid gaussian) → less certain → lower confidence
 */
function computeTemporalConfidence(
  gaussianValue: number,
  windowCount: number
): number {
  let base: number;
  if (gaussianValue > 0.5) {
    // Near a known peak — confident it's busy
    base = 0.6;
  } else if (gaussianValue < 0.1) {
    // Deep trough — confident it's quiet
    base = 0.55;
  } else {
    // Transitional — less certain
    base = 0.45;
  }

  // More popular windows = more historical data = slightly more confident
  const dataBonus = Math.min(0.1, windowCount * 0.03);

  return Math.min(0.7, base + dataBonus);
}

/** Parse "HH:mm" or "HHmm" time string to minutes since midnight. */
function parseTimeToMinutes(time: string): number {
  const clean = time.replace(":", "");
  const h = parseInt(clean.slice(0, 2), 10);
  const m = parseInt(clean.slice(2, 4), 10) || 0;
  return h * 60 + m;
}
