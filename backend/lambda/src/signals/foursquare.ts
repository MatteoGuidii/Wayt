import {
  venueKey,
  mappingSK,
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

    // Return ephemeral signal — no signal-level caching needed since the
    // raw data is cached for 30 days and the score depends on current time
    return {
      sourceId: "foursquare",
      venueId,
      busynessScore,
      confidence,
      baseWeight: config.weight,
      timestamp: now,
      ttlSeconds: config.ttlSeconds,
    };
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
// Time-aware busyness scoring
// -----------------------------------------------

/**
 * Compute a time-aware busyness score from cached Foursquare data.
 *
 * Foursquare's `popularity` is a static all-time popularity ranking, NOT a
 * real-time busyness indicator. We use `hoursPopular` to determine if the
 * venue is currently in a popular window and scale the score accordingly.
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

  // Without hours_popular, we can't tell if the venue is busy right now
  if (data.hoursPopular.length === 0) {
    return {
      score: popularity * 0.3,
      confidence: 0.3,
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
      score: popularity * 0.15,
      confidence: 0.4,
    };
  }

  // Check if current time falls within or near a popular window
  let bestProximity = Infinity;
  let insideWindow = false;

  for (const w of todayWindows) {
    if (currentMinutes >= w.open && currentMinutes <= w.close) {
      insideWindow = true;
      bestProximity = 0;
      break;
    }
    const distToOpen = w.open - currentMinutes;
    const distToClose = currentMinutes - w.close;
    const dist = Math.min(
      distToOpen > 0 ? distToOpen : Infinity,
      distToClose > 0 ? distToClose : Infinity
    );
    bestProximity = Math.min(bestProximity, dist);
  }

  const EDGE_MINUTES = 60; // interpolation zone around popular windows

  if (insideWindow) {
    return {
      score: popularity * 0.7,
      confidence: 0.6,
    };
  }

  if (bestProximity <= EDGE_MINUTES) {
    const t = bestProximity / EDGE_MINUTES;
    const peakFactor = 0.7;
    const offPeakFactor = 0.2;
    const factor = peakFactor + (offPeakFactor - peakFactor) * t;
    return {
      score: popularity * factor,
      confidence: 0.5,
    };
  }

  // Well outside popular hours
  return {
    score: popularity * 0.15,
    confidence: 0.4,
  };
}

/** Parse "HH:mm" or "HHmm" time string to minutes since midnight. */
function parseTimeToMinutes(time: string): number {
  const clean = time.replace(":", "");
  const h = parseInt(clean.slice(0, 2), 10);
  const m = parseInt(clean.slice(2, 4), 10) || 0;
  return h * 60 + m;
}
