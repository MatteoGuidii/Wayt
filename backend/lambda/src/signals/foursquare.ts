import {
  venueKey,
  mappingSK,
  signalSK,
  getItem,
  putItem,
} from "../db";
import { haversineDistance } from "../shared";
import { VenueSignal, SOURCE_CONFIG, VenueCategory } from "./types";
import { createLogger } from "../logger";
import {
  nameSimilarity,
  MATCH_MAX_DISTANCE_M,
  MATCH_MIN_SCORE,
  getLocalTime,
} from "./matching";
import { foursquareBreaker } from "./circuitBreaker";

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

interface FsqSearchResult {
  fsq_place_id: string;
  name: string;
  popularity?: number;
  rating?: number;
  distance?: number;
  hours_popular?: Array<{ day: number; open: string; close: string }>;
  stats?: { total_photos?: number; total_tips?: number; total_ratings?: number };
  /** Top-level coordinates returned by Foursquare search. */
  latitude?: number;
  longitude?: number;
}

interface FsqSearchResponse {
  results?: FsqSearchResult[];
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
export interface CachedFsqData {
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
  lng: number,
  timezone: string = "UTC",
  address?: string,
  category: VenueCategory = "default"
): Promise<VenueSignal | null> {
  if (!FOURSQUARE_API_KEY) return null;

  const log = createLogger("foursquare");

  try {
    // Step 1: Get raw Foursquare data (from 30-day cache or fresh API call)
    const data = await getFoursquareVenueData(venueId, venueName, lat, lng, address);
    if (!data) {
      log.debug("No FSQ data available", { venueId });
      return null;
    }

    // Step 2: Compute time-aware score from cached data + current time
    const now = Date.now();
    const { score: busynessScore, confidence } = computeTimeAwareBusyness(data, now, timezone, undefined, category);
    log.debug("Signal computed", { venueId, busynessScore: Math.round(busynessScore * 1000) / 1000, confidence: Math.round(confidence * 100) / 100 });
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
    log.error("Failed to fetch signal", { venueId }, err);
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
  lng: number,
  address?: string
): Promise<CachedFsqData | null> {
  const log = createLogger("foursquare:data");

  // Check cache first
  const cached = await getItem(venueKey(venueId), FSQDATA_SK);
  if (cached) {
    const ttl = cached.ttl as number | undefined;
    if (!ttl || ttl >= Math.floor(Date.now() / 1000)) {
      log.debug("FSQDATA cache hit", { venueId });
      return {
        popularity: (cached.popularity as number | null) ?? null,
        rating: (cached.rating as number | null) ?? null,
        hoursPopular: (cached.hoursPopular as CachedFsqData["hoursPopular"]) ?? [],
      };
    }
    log.debug("FSQDATA cache expired", { venueId });
  }

  // Cache miss — fetch from Foursquare API
  const fsqId = await getCachedMapping(venueId) ?? await matchVenue(venueId, venueName, lat, lng, address);
  if (!fsqId) {
    log.debug("No Foursquare match", { venueId, venueName });
    return null;
  }

  const details = await fetchPlaceDetails(fsqId);
  if (!details) {
    log.warn("fetchPlaceDetails returned null", { venueId, fsqId });
    return null;
  }

  log.debug("Got place details", { venueId, fsqId, popularity: details.popularity, hoursCount: details.hours_popular?.length ?? 0 });

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

/** Per-request timeout in milliseconds. Prevents a single stalled request from blocking the Lambda. */
const FETCH_TIMEOUT_MS = 4_000;

/** Fetch with retry, exponential backoff, circuit breaker, and per-request timeout. */
async function fetchWithRetry(
  url: string,
  label: string,
  maxRetries = 3
): Promise<Response | null> {
  if (!foursquareBreaker.allowRequest()) {
    const log = createLogger("foursquare");
    log.warn("Circuit breaker OPEN — skipping request", { label });
    return null;
  }

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
      const response = await fetch(url, { headers: FSQ_HEADERS, signal: controller.signal });
      clearTimeout(timeout);

      if (response.ok) {
        foursquareBreaker.recordSuccess();
        return response;
      }

      const retryable = response.status === 429 || response.status >= 500;
      if (!retryable || attempt === maxRetries) {
        foursquareBreaker.recordFailure();
        const retryLog = createLogger("foursquare");
        let body = "(empty)";
        try {
          const raw = await response.text();
          if (raw) body = raw.slice(0, 300);
        } catch { /* ignore */ }
        retryLog.warn("API request failed", {
          label,
          url: url.slice(0, 200),
          status: response.status,
          attempt: attempt + 1,
          maxRetries: maxRetries + 1,
          responseBody: body,
          circuitState: foursquareBreaker.getState(),
        });
        return null;
      }

      // Exponential backoff with jitter: 200-300ms, 400-500ms, 800-900ms
      const delayMs = 200 * Math.pow(2, attempt) + Math.random() * 100;
      const retryLog = createLogger("foursquare");
      retryLog.debug("Retrying API request", {
        label,
        status: response.status,
        attempt: attempt + 1,
        delayMs: Math.round(delayMs),
      });
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    } catch (err) {
      // Network error or timeout
      foursquareBreaker.recordFailure();
      if (attempt === maxRetries) {
        const log = createLogger("foursquare");
        log.warn("API request error (network/timeout)", {
          label,
          attempt: attempt + 1,
          error: err instanceof Error ? err.message : String(err),
          circuitState: foursquareBreaker.getState(),
        });
        return null;
      }
      const delayMs = 200 * Math.pow(2, attempt) + Math.random() * 100;
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
  return null;
}


/** Search for a venue by name + coordinates and return the best Foursquare place ID. */
async function matchVenue(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number,
  address?: string
): Promise<string | null> {
  const log = createLogger("foursquare:match");

  const params = new URLSearchParams({
    query: venueName,
    limit: "5",
  });
  // Foursquare requires either `ll` or `near`, not both.
  // Prefer `near` when address is available — MapKit coordinates can be
  // several km off while the address is usually correct.
  if (address) {
    params.set("near", address);
  } else {
    params.set("ll", `${lat},${lng}`);
  }

  const response = await fetchWithRetry(
    `${FSQ_BASE}/places/search?${params}`,
    `Search for "${venueName}"`
  );
  if (!response) return null;

  const data = (await response.json()) as FsqSearchResponse;
  const candidates = data.results ?? [];
  if (candidates.length === 0) return null;

  // Score each candidate by name similarity + distance
  let bestCandidate: (typeof candidates)[0] | null = null;
  let bestScore = -1;

  for (const candidate of candidates) {
    const distance = candidate.distance ?? Infinity;
    if (distance > MATCH_MAX_DISTANCE_M) continue;

    const distanceScore = Math.max(0, 1.0 - distance / MATCH_MAX_DISTANCE_M);
    const nameScore = nameSimilarity(venueName, candidate.name);
    const score = 0.4 * distanceScore + 0.6 * nameScore;

    if (score > bestScore) {
      bestScore = score;
      bestCandidate = candidate;
    }
  }

  if (!bestCandidate || bestScore < MATCH_MIN_SCORE) {
    log.debug("No match passed threshold", {
      venueId,
      venueName,
      candidateCount: candidates.length,
      bestScore: bestScore.toFixed(3),
    });
    return null;
  }

  const fsqId = bestCandidate.fsq_place_id;
  log.debug("Matched venue", {
    venueId,
    venueName,
    fsqName: bestCandidate.name,
    distance: bestCandidate.distance,
    score: bestScore.toFixed(3),
  });

  // Cache the mapping for 30 days
  const now = Math.floor(Date.now() / 1000);
  await putItem({
    PK: venueKey(venueId),
    SK: mappingSK("foursquare"),
    fsqId,
    fsqName: bestCandidate.name,
    matchScore: bestScore,
    matchDistance: bestCandidate.distance,
    cachedAt: new Date().toISOString(),
    ttl: now + MAPPING_TTL_DAYS * 86_400,
  });

  return fsqId;
}

/** Fetch Foursquare place details including popularity. */
async function fetchPlaceDetails(fsqId: string): Promise<FsqPlaceDetails | null> {
  const log = createLogger("foursquare:data");
  const fields = "fsq_place_id,name,popularity,rating,stats,hours_popular";
  const response = await fetchWithRetry(
    `${FSQ_BASE}/places/${fsqId}?fields=${fields}`,
    `Details for fsq_id=${fsqId}`
  );
  if (!response) return null;

  const data = (await response.json()) as FsqPlaceDetails;
  log.debug("Place details fetched", {
    fsqId,
    name: data.name,
    hasPopularity: data.popularity != null,
    popularity: data.popularity,
    hoursPopularCount: data.hours_popular?.length ?? 0,
  });
  return data;
}

// -----------------------------------------------
// Gaussian temporal busyness model
// -----------------------------------------------

/**
 * Category-aware day-of-week amplitude multipliers (1=Mon..7=Sun).
 * Different venue types have fundamentally different weekly patterns:
 * - Coffee: weekday mornings are peak (commuters), weekends quieter
 * - Bars: Thu–Sat are strong, Mon–Wed very quiet
 * - Nightclubs: extreme Fri–Sat skew, nearly dead Mon–Wed
 * - Restaurants: original pattern (Sat peak, gradual weekday build)
 */
export const CATEGORY_DAY_MULTIPLIERS: Record<VenueCategory, Record<number, number>> = {
  restaurant: { 1: 0.55, 2: 0.60, 3: 0.65, 4: 0.75, 5: 0.95, 6: 1.00, 7: 0.70 },
  coffee:     { 1: 0.95, 2: 0.95, 3: 0.95, 4: 0.95, 5: 0.90, 6: 0.75, 7: 0.65 },
  bar:        { 1: 0.35, 2: 0.40, 3: 0.50, 4: 0.70, 5: 1.00, 6: 0.95, 7: 0.45 },
  nightclub:  { 1: 0.15, 2: 0.15, 3: 0.25, 4: 0.50, 5: 0.95, 6: 1.00, 7: 0.30 },
  default:    { 1: 0.55, 2: 0.60, 3: 0.65, 4: 0.75, 5: 0.95, 6: 1.00, 7: 0.70 },
};

/** @deprecated Use CATEGORY_DAY_MULTIPLIERS instead. Kept for backward compat. */
export const DAY_MULTIPLIERS = CATEGORY_DAY_MULTIPLIERS.default;

// -----------------------------------------------
// Asymmetric temporal curve parameters
// -----------------------------------------------

interface TemporalCurveParams {
  /** Where peak falls within the window: 0.0 = start, 1.0 = end. */
  peakPosition: number;
  /** Sigma multiplier for the ramp-up (left) side. Larger = more gradual. */
  sigmaLeftScale: number;
  /** Sigma multiplier for the taper-off (right) side. Larger = longer tail. */
  sigmaRightScale: number;
}

/**
 * Category-specific curve shapes reflecting real-world arrival/departure patterns.
 * Uses a split-normal (piecewise Gaussian with different left/right sigma).
 */
const CATEGORY_CURVES: Record<VenueCategory, TemporalCurveParams> = {
  restaurant: { peakPosition: 0.40, sigmaLeftScale: 0.20, sigmaRightScale: 0.35 },
  coffee:     { peakPosition: 0.25, sigmaLeftScale: 0.15, sigmaRightScale: 0.40 },
  bar:        { peakPosition: 0.65, sigmaLeftScale: 0.30, sigmaRightScale: 0.20 },
  nightclub:  { peakPosition: 0.75, sigmaLeftScale: 0.35, sigmaRightScale: 0.15 },
  default:    { peakPosition: 0.45, sigmaLeftScale: 0.25, sigmaRightScale: 0.30 },
};

/**
 * Compute a time-aware busyness score using category-aware asymmetric curves.
 *
 * Each popular window becomes an asymmetric bell curve (split-normal) whose
 * shape varies by venue category: restaurants peak early with a lingering tail,
 * bars peak late and stay packed, coffee shops spike at opening.
 *
 * Popularity is transformed via sqrt to prevent low-popularity venues from
 * being invisible at their peak times.
 *
 * Based on "Predicting Temporal Activity Patterns of New Venues" (EPJ Data
 * Science, 2018) and industry foot traffic research.
 */
export function computeTimeAwareBusyness(
  data: CachedFsqData,
  nowMs: number,
  timezone: string = "UTC",
  isOpen?: boolean | null,
  category: VenueCategory = "default"
): { score: number; confidence: number } {
  // When Google hours confirm venue is closed, short-circuit to zero
  if (isOpen === false) {
    return { score: 0.0, confidence: 0.85 };
  }

  const basePopularity = data.popularity ?? (data.rating != null ? data.rating / 10 : null);

  if (basePopularity == null) {
    return { score: 0.5, confidence: 0.2 };
  }

  const popularity = Math.max(0, Math.min(1, basePopularity));

  // Convert UTC time to the venue's local time using Intl API
  const { localDay, localMinutes } = getLocalTime(nowMs, timezone);
  // Convert JS day (0=Sun,1=Mon..6=Sat) to Foursquare convention (1=Mon..7=Sun)
  const currentDay = localDay === 0 ? 7 : localDay;
  const currentMinutes = localMinutes;

  // Without hours_popular we have no temporal shape — weak baseline only
  if (data.hoursPopular.length === 0) {
    return {
      score: popularityToIntensity(popularity) * 0.15,
      confidence: 0.25,
    };
  }

  // Find popular windows for today (handle midnight-crossing windows)
  // Use strict < to avoid treating degenerate zero-length windows (close===open) as 24h
  const todayWindows = data.hoursPopular
    .filter((h) => h.day === currentDay)
    .map((h) => {
      const open = parseTimeToMinutes(h.open);
      let close = parseTimeToMinutes(h.close);
      if (close < open) close += 1440; // Extend past midnight
      return { open, close };
    });

  // Also include yesterday's windows that cross midnight into today
  const yesterdayFsq = currentDay === 1 ? 7 : currentDay - 1;
  const midnightSpill = data.hoursPopular
    .filter((h) => h.day === yesterdayFsq)
    .map((h) => ({
      open: parseTimeToMinutes(h.open),
      close: parseTimeToMinutes(h.close),
    }))
    .filter((w) => w.close < w.open) // Only windows that cross midnight (strict <)
    .map((w) => ({
      open: w.open - 1440, // Shift to "yesterday" frame
      close: w.close,      // Close is already in "today" minutes
    }));

  const allWindows = [...todayWindows, ...midnightSpill];

  if (allWindows.length === 0) {
    // Check if Foursquare has popular hours for OTHER days but not today
    const hasOtherDays = data.hoursPopular.some((h) => h.day !== currentDay);
    if (hasOtherDays) {
      // Data exists for other days but not today — likely closed or very quiet
      return { score: popularityToIntensity(popularity) * 0.05, confidence: 0.6 };
    }
    // No popular hours for any day — Foursquare lacks data
    return { score: popularityToIntensity(popularity) * 0.05, confidence: 0.25 };
  }

  // Sum of asymmetric kernels: each window contributes a split-normal curve
  const curveParams = CATEGORY_CURVES[category];
  let kernelSum = 0;
  for (const w of allWindows) {
    kernelSum += asymmetricKernel(currentMinutes, w.open, w.close, curveParams);
  }

  // Clamp to [0, 1] — overlapping peaks can sum above 1
  const temporalShape = Math.min(1, kernelSum);

  // Category-aware day-of-week amplitude scaling
  const dayMults = CATEGORY_DAY_MULTIPLIERS[category];
  const dayMult = dayMults[currentDay] ?? 0.7;

  // Transform popularity into peak intensity (sqrt compresses range so
  // low-popularity venues still show busyness at peak)
  const peakIntensity = popularityToIntensity(popularity);

  // Final score: day multiplier × temporal shape × peak intensity
  const score = Math.min(1, dayMult * temporalShape * peakIntensity);

  // Confidence: lower than before — this is historical data, not real-time
  const confidence = computeTemporalConfidence(temporalShape, allWindows.length, category);

  const log = createLogger("foursquare");
  log.debug("Temporal busyness computed", {
    category,
    popularity: popularity.toFixed(3),
    peakIntensity: peakIntensity.toFixed(3),
    dayMultiplier: dayMult,
    currentDay,
    currentMinutes,
    windowCount: allWindows.length,
    kernelSum: kernelSum.toFixed(3),
    temporalShape: temporalShape.toFixed(3),
    score: score.toFixed(3),
    confidence: confidence.toFixed(3),
  });

  return { score, confidence };
}

/**
 * Asymmetric kernel (split-normal): uses different sigma on the left (ramp-up)
 * and right (taper-off) sides of the peak. Same computational cost as a
 * standard Gaussian — just one Math.exp per window.
 */
function asymmetricKernel(
  currentMinutes: number,
  windowOpen: number,
  windowClose: number,
  params: TemporalCurveParams
): number {
  const duration = windowClose - windowOpen;
  if (duration <= 0) return 0;

  // Peak position in absolute minutes
  const mu = windowOpen + duration * params.peakPosition;

  // Sigma values derived from window duration (min 10 min to avoid sharp spikes)
  const sigmaLeft = Math.max(duration * params.sigmaLeftScale, 10);
  const sigmaRight = Math.max(duration * params.sigmaRightScale, 10);

  const diff = currentMinutes - mu;
  const sigma = diff <= 0 ? sigmaLeft : sigmaRight;

  return Math.exp(-(diff * diff) / (2 * sigma * sigma));
}

/**
 * Transform Foursquare popularity (0-1, a relative 6-month ranking) into
 * peak intensity (0-1) for the busyness formula.
 *
 * Uses sqrt to compress the range: a venue with popularity 0.1 still gets
 * intensity ~0.52 at peak, while popularity 0.9 → ~0.96. This prevents
 * small but packed venues from being invisible on the map.
 */
function popularityToIntensity(popularity: number): number {
  return 0.3 + 0.7 * Math.sqrt(Math.max(0, Math.min(1, popularity)));
}

/**
 * Confidence for Foursquare temporal predictions. Deliberately lower than before
 * because this is 6-month aggregate data, not real-time observation.
 *
 * Max confidence is 0.55 (was 0.85), ensuring single-source Foursquare
 * predictions map to "LOW" in the fusion engine (threshold for "MEDIUM" is 0.6).
 */
function computeTemporalConfidence(
  temporalShape: number,
  windowCount: number,
  category: VenueCategory
): number {
  let base: number;
  if (temporalShape > 0.5) {
    // Near a known peak — somewhat confident (historical pattern)
    base = 0.40;
  } else if (temporalShape < 0.1) {
    // Deep trough — slightly less confident (venue might have an event)
    base = 0.35;
  } else {
    // Transitional — low confidence
    base = 0.25;
  }

  // More popular windows = more historical data = slightly more confident
  const dataBonus = Math.min(0.10, windowCount * 0.03);

  // Well-established pattern categories get a small boost
  const categoryBonus = (category === "coffee" || category === "nightclub") ? 0.05 : 0;

  return Math.min(0.55, base + dataBonus + categoryBonus);
}


/** Parse "HH:mm" or "HHmm" time string to minutes since midnight. */
function parseTimeToMinutes(time: string): number {
  const clean = time.replace(":", "");
  const h = parseInt(clean.slice(0, 2), 10);
  const m = parseInt(clean.slice(2, 4), 10) || 0;
  return h * 60 + m;
}

// -----------------------------------------------
// Batch area search (replaces N individual searches with 2-3 area queries)
// -----------------------------------------------

/** Foursquare category IDs for dining & drinking. */
const FSQ_DINING_CATEGORIES = "13000";  // Food & Dining (covers restaurants, cafes, bars, bakeries, etc.)

/** Result of matching a client venue to a Foursquare place via batch area search. */
export interface BatchMatchResult {
  fsqId: string;
  fsqName: string;
  matchScore: number;
  data: CachedFsqData;
}

/**
 * Perform 1-3 Foursquare area searches and match results to client venues.
 *
 * Instead of N individual `matchVenue()` calls (2 API calls each), this does
 * 1-3 area searches that return up to 50 results each, including `hours_popular`.
 * Venues are matched using the same name similarity + distance scoring.
 *
 * Caches mappings and raw data for all matched venues (30-day TTL).
 */
export async function batchMatchVenues(
  venues: Array<{ venueId: string; venueName: string; lat: number; lng: number }>,
  centerLat: number,
  centerLng: number,
  radiusMeters: number
): Promise<Map<string, BatchMatchResult>> {
  if (!FOURSQUARE_API_KEY || venues.length === 0) {
    return new Map();
  }

  const log = createLogger("foursquare:batch");
  const results = new Map<string, BatchMatchResult>();

  // Clamp radius to Foursquare's max of 100km, practical max ~5km for our use case
  const radius = Math.min(Math.max(radiusMeters, 500), 100_000);

  // Fetch Foursquare places in the area (up to 50 per call)
  const fsqPlaces = await batchSearchArea(centerLat, centerLng, radius, log);
  if (fsqPlaces.length === 0) return results;

  log.info("Batch search returned places", {
    count: fsqPlaces.length,
    sampleName: fsqPlaces[0]?.name,
    sampleLat: fsqPlaces[0]?.latitude,
    sampleDistance: fsqPlaces[0]?.distance,
  });

  // Match each client venue against the Foursquare pool
  const nowSeconds = Math.floor(Date.now() / 1000);
  const cachePuts: Promise<void>[] = [];

  for (const venue of venues) {
    let bestResult: FsqSearchResult | null = null;
    let bestScore = -1;

    for (const fsq of fsqPlaces) {
      // Compute distance between client venue and Foursquare result
      const fsqLat = fsq.latitude;
      const fsqLng = fsq.longitude;
      let distance: number;

      if (fsqLat != null && fsqLng != null) {
        distance = haversineDistance(venue.lat, venue.lng, fsqLat, fsqLng);
      } else if (fsq.distance != null) {
        // Fallback: use distance from center (less accurate but usable)
        distance = fsq.distance;
      } else {
        continue;
      }

      if (distance > MATCH_MAX_DISTANCE_M) continue;

      const distanceScore = Math.max(0, 1.0 - distance / MATCH_MAX_DISTANCE_M);
      const nameScore = nameSimilarity(venue.venueName, fsq.name);
      const score = 0.4 * distanceScore + 0.6 * nameScore;

      if (score > bestScore) {
        bestScore = score;
        bestResult = fsq;
      }
    }

    if (!bestResult || bestScore < MATCH_MIN_SCORE) continue;

    const data: CachedFsqData = {
      popularity: bestResult.popularity ?? null,
      rating: bestResult.rating ?? null,
      hoursPopular: bestResult.hours_popular ?? [],
    };

    results.set(venue.venueId, {
      fsqId: bestResult.fsq_place_id,
      fsqName: bestResult.name,
      matchScore: bestScore,
      data,
    });

    // Cache mapping + raw data in parallel (fire-and-forget within the batch)
    cachePuts.push(
      putItem({
        PK: venueKey(venue.venueId),
        SK: mappingSK("foursquare"),
        fsqId: bestResult.fsq_place_id,
        fsqName: bestResult.name,
        matchScore: bestScore,
        cachedAt: new Date().toISOString(),
        ttl: nowSeconds + MAPPING_TTL_DAYS * 86_400,
      }),
      putItem({
        PK: venueKey(venue.venueId),
        SK: FSQDATA_SK,
        ...data,
        cachedAt: new Date().toISOString(),
        ttl: nowSeconds + DATA_TTL_DAYS * 86_400,
      })
    );
  }

  // Wait for all cache writes
  await Promise.all(cachePuts);

  log.info("Batch matching complete", {
    clientVenues: venues.length,
    matched: results.size,
    unmatched: venues.length - results.size,
  });

  return results;
}

/**
 * Search Foursquare for venues in an area.
 * For small areas (≤1500m radius): 2 parallel queries (category + broad) — up to 100 results.
 * For larger areas: splits into 4 quadrants with category queries + 1 broad center query,
 * increasing coverage to ~250 deduplicated results and reducing Phase 3 cold venue fallback.
 */
async function batchSearchArea(
  lat: number,
  lng: number,
  radiusMeters: number,
  log: ReturnType<typeof createLogger>
): Promise<FsqSearchResult[]> {
  const fields = "fsq_place_id,name,popularity,rating,distance,hours_popular,latitude,longitude";

  const searches: Promise<FsqSearchResult[]>[] = [];

  if (radiusMeters <= 1500) {
    // Small area: 2 parallel searches (original strategy)
    const radiusStr = String(Math.round(radiusMeters));
    const ll = `${lat},${lng}`;
    searches.push(
      fetchAreaSearch({ ll, radius: radiusStr, categories: FSQ_DINING_CATEGORIES, limit: "50", fields }),
      fetchAreaSearch({ ll, radius: radiusStr, limit: "50", fields }),
    );
  } else {
    // Large area: split into quadrants for category search + 1 broad center search.
    // Each quadrant covers half the radius, offsetting center by ~40% of the radius.
    const offset = radiusMeters * 0.4;
    const latOffset = offset / 111_320; // ~111km per degree latitude
    const lngOffset = offset / (111_320 * Math.cos(lat * Math.PI / 180));
    const quadrantRadius = String(Math.round(radiusMeters * 0.55));

    const quadrants = [
      { lat: lat + latOffset, lng: lng + lngOffset },
      { lat: lat + latOffset, lng: lng - lngOffset },
      { lat: lat - latOffset, lng: lng + lngOffset },
      { lat: lat - latOffset, lng: lng - lngOffset },
    ];

    // 4 quadrant category searches + 1 broad center search (5 parallel calls)
    for (const q of quadrants) {
      searches.push(
        fetchAreaSearch({
          ll: `${q.lat},${q.lng}`,
          radius: quadrantRadius,
          categories: FSQ_DINING_CATEGORIES,
          limit: "50",
          fields,
        }),
      );
    }
    searches.push(
      fetchAreaSearch({ ll: `${lat},${lng}`, radius: String(Math.round(radiusMeters)), limit: "50", fields }),
    );
  }

  const results = await Promise.all(searches);

  // Deduplicate by fsq_place_id
  const seen = new Set<string>();
  const combined: FsqSearchResult[] = [];
  for (const batch of results) {
    for (const place of batch) {
      if (!seen.has(place.fsq_place_id)) {
        seen.add(place.fsq_place_id);
        combined.push(place);
      }
    }
  }

  log.debug("Area search results", {
    queries: results.length,
    totalRaw: results.reduce((sum, r) => sum + r.length, 0),
    deduplicated: combined.length,
  });
  return combined;
}

/** Execute a single Foursquare area search with given params. */
async function fetchAreaSearch(
  params: Record<string, string>
): Promise<FsqSearchResult[]> {
  const log = createLogger("foursquare:batch");
  const searchParams = new URLSearchParams(params);
  const response = await fetchWithRetry(
    `${FSQ_BASE}/places/search?${searchParams}`,
    `Area search`
  );
  if (!response) {
    log.warn("Area search returned no response", {
      ll: params.ll,
      radius: params.radius,
      categories: params.categories ?? "none",
    });
    return [];
  }

  const data = (await response.json()) as FsqSearchResponse;
  return data.results ?? [];
}

