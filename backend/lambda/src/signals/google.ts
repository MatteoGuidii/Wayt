/**
 * Google Places API integration for operating hours, categories, ratings,
 * reviews, and pricing.
 *
 * Supplements Foursquare (busyness signals) with Google's regularOpeningHours
 * to provide reliable open/closed status, and adds venue metadata (types,
 * rating, reviews, priceLevel, editorialSummary) for richer venue detail.
 *
 * Two-tier pricing strategy:
 * - **Basic tier** ($5/1K): hours, business status, types — used by
 *   getGoogleHoursData() for map/list views (high volume).
 * - **Enterprise tier** ($25/1K): rating, reviews, price — fetched lazily
 *   via ensureVenueDetails() only when a user opens a venue detail view.
 *
 * Caching: 30-day TTL on venue mapping, hours data, and venue details.
 * Failed match attempts cached for 7 days to avoid wasteful retries.
 */

import {
  venueKey,
  mappingSK,
  getItem,
  putItem,
} from "../db";
import { haversineDistance } from "../shared";
import { createLogger } from "../logger";
import {
  nameSimilarity,
  MATCH_MAX_DISTANCE_M,
  MATCH_MIN_SCORE,
  getLocalTime,
} from "./matching";
import { CachedVenueDetails } from "./types";
import { googleBreaker } from "./circuitBreaker";

const GOOGLE_API_KEY = process.env.GOOGLE_PLACES_API_KEY ?? "";
const GOOGLE_BASE = "https://places.googleapis.com/v1";
const MAPPING_TTL_DAYS = 30;
const DATA_TTL_DAYS = 30;
/** TTL for caching a failed Google match attempt (hours).
 * 7 days avoids hammering Google with repeated Text Search calls for
 * venues that don't exist in Google's database. Google's POI data
 * updates infrequently, so retrying sooner wastes API budget. */
const FAILED_MATCH_TTL_HOURS = 168;

// -----------------------------------------------
// Types
// -----------------------------------------------

/** A single opening period from Google's regularOpeningHours. */
export interface GoogleOpenPeriod {
  openDay: number;     // 0=Sunday (Google convention)
  openHour: number;
  openMinute: number;
  closeDay: number;
  closeHour: number;
  closeMinute: number;
}

/** Cached Google hours data stored in DynamoDB. */
export interface CachedGoogleHours {
  businessStatus: "OPERATIONAL" | "CLOSED_TEMPORARILY" | "CLOSED_PERMANENTLY" | null;
  regularPeriods: GoogleOpenPeriod[];
  cachedAt: string;
}

/** Result of isOpenNow() check. */
export interface OpenStatus {
  isOpen: boolean;
  hoursToday: string | null;  // e.g. "11:00 AM – 10:00 PM"
}

// -----------------------------------------------
// Google Places API response shapes
// -----------------------------------------------

interface GoogleSearchResult {
  places?: Array<{
    id: string;
    displayName?: { text: string };
    location?: { latitude: number; longitude: number };
  }>;
}

interface GoogleMoney {
  currencyCode?: string;
  units?: string;
  nanos?: number;
}

interface GooglePlaceDetails {
  businessStatus?: string;
  regularOpeningHours?: {
    periods?: Array<{
      open: { day: number; hour: number; minute: number };
      close?: { day: number; hour: number; minute: number };
    }>;
  };
  types?: string[];
  primaryType?: string;
  primaryTypeDisplayName?: { text: string; languageCode?: string };
  rating?: number;
  userRatingCount?: number;
  priceLevel?: string;
  priceRange?: {
    startPrice?: GoogleMoney;
    endPrice?: GoogleMoney;
  };
  reviews?: Array<{
    authorAttribution?: { displayName?: string };
    rating?: number;
    text?: { text: string };
    relativePublishTimeDescription?: string;
    publishTime?: string;
  }>;
  editorialSummary?: { text: string };
}

// -----------------------------------------------
// Public API
// -----------------------------------------------

const GDATA_SK = "GDATA#CURRENT";
const GDETAILS_SK = "GDETAILS#CURRENT";

/** Return type for getGoogleHoursData — hours plus any venue details fetched in the same API call. */
export interface GoogleHoursResult {
  hours: CachedGoogleHours;
  venueDetails: CachedVenueDetails | null;
}

/**
 * Get cached Google hours data for a venue, fetching from API on cache miss.
 * Returns hours and venue details (categories, rating, reviews, price) when
 * fetched from the API. On cache hit, venueDetails is null (callers should
 * use getGoogleVenueDetails() or batch-read GDETAILS#CURRENT separately).
 */
export async function getGoogleHoursData(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number,
  address?: string
): Promise<GoogleHoursResult | null> {
  if (!GOOGLE_API_KEY) return null;

  const log = createLogger("google");

  try {
    // Check cache first
    const cached = await getItem(venueKey(venueId), GDATA_SK);
    if (cached) {
      const ttl = cached.ttl as number | undefined;
      if (!ttl || ttl >= Math.floor(Date.now() / 1000)) {
        log.debug("GDATA cache hit", { venueId });
        return {
          hours: {
            businessStatus: (cached.businessStatus as CachedGoogleHours["businessStatus"]) ?? null,
            regularPeriods: (cached.regularPeriods as GoogleOpenPeriod[]) ?? [],
            cachedAt: cached.cachedAt as string,
          },
          venueDetails: null,
        };
      }
      log.debug("GDATA cache expired", { venueId });
    }

    // Cache miss — resolve Google Place ID
    const cachedMapping = await getCachedGoogleMapping(venueId);

    // If we recently failed to match this venue, don't retry until TTL expires
    if (cachedMapping === NO_MATCH_SENTINEL) {
      log.debug("Skipping Google match — cached failure", { venueId });
      return null;
    }

    const googlePlaceId = cachedMapping ?? await matchGoogleVenue(venueId, venueName, lat, lng, address);
    if (!googlePlaceId) {
      log.debug("No Google Place ID resolved", { venueId, venueName });
      // Cache the failure so we don't re-attempt on every request
      const now = Math.floor(Date.now() / 1000);
      await putItem({
        PK: venueKey(venueId),
        SK: mappingSK("google"),
        googlePlaceId: NO_MATCH_SENTINEL,
        venueName,
        cachedAt: new Date().toISOString(),
        ttl: now + FAILED_MATCH_TTL_HOURS * 3_600,
      });
      return null;
    }

    // Fetch hours + types from Google Places API — Basic tier ($5/1K).
    // Enterprise fields (rating, reviews, price) are fetched lazily via
    // ensureVenueDetails() only when a user taps into a venue detail view.
    const details = await fetchGooglePlaceBasic(googlePlaceId);
    if (!details) return null;

    const cachedAt = new Date().toISOString();

    const data: CachedGoogleHours = {
      businessStatus: normalizeBusinessStatus(details.businessStatus),
      regularPeriods: (details.regularOpeningHours?.periods ?? []).map((p) => ({
        openDay: p.open.day,
        openHour: p.open.hour,
        openMinute: p.open.minute,
        closeDay: p.close?.day ?? p.open.day,
        closeHour: p.close?.hour ?? 23,
        closeMinute: p.close?.minute ?? 59,
      })),
      cachedAt,
    };

    // Extract Basic-tier venue details (types only — no rating/reviews/price)
    const venueDetails: CachedVenueDetails = {
      types: details.types ?? [],
      primaryType: details.primaryType ?? null,
      primaryTypeDisplayName: details.primaryTypeDisplayName?.text ?? null,
      rating: null,
      userRatingCount: null,
      priceLevel: null,
      priceRange: null,
      reviews: [],
      editorialSummary: null,
      cachedAt,
    };

    // Cache hours (critical) and Basic-tier details (best-effort) with 30-day TTL.
    const nowSeconds = Math.floor(Date.now() / 1000);
    const ttl = nowSeconds + DATA_TTL_DAYS * 86_400;
    await putItem({
      PK: venueKey(venueId),
      SK: GDATA_SK,
      ...data,
      ttl,
    });
    // Best-effort write for Basic-tier venue details (types/primaryType)
    putItem({
      PK: venueKey(venueId),
      SK: GDETAILS_SK,
      ...venueDetails,
      ttl,
    }).catch((err) => {
      log.warn("Failed to cache venue details", { venueId, error: err instanceof Error ? err.message : String(err) });
    });

    return { hours: data, venueDetails };
  } catch (err) {
    log.error("Failed to fetch Google hours", { venueId }, err);
    return null;
  }
}

/**
 * Ensure venue details (categories, rating, reviews, price) exist in DynamoDB.
 * Reads from cache first; on miss, resolves the Google Place ID from the cached
 * mapping and fetches details from the Google Places API. Used to backfill
 * GDETAILS#CURRENT for venues that had hours cached before details were added.
 *
 * Returns null if no Google mapping exists or API fetch fails.
 * Safe to call concurrently — worst case is a duplicate write.
 */
export async function ensureVenueDetails(venueId: string): Promise<CachedVenueDetails | null> {
  const log = createLogger("google:backfill");

  // Check if already cached with Enterprise-tier fields populated.
  // Basic-tier entries (from getGoogleHoursData) don't have the
  // enterpriseFetched marker — those need upgrading.
  const existing = await getGoogleVenueDetails(venueId);
  if (existing?.enterpriseFetched) {
    return existing;
  }

  // Read cached Google mapping to get the Place ID
  const mapping = await getItem(venueKey(venueId), mappingSK("google"));
  if (!mapping) return null;
  const googlePlaceId = mapping.googlePlaceId as string;
  if (!googlePlaceId || googlePlaceId === NO_MATCH_SENTINEL) return null;

  // Fetch Enterprise-tier fields (rating, reviews, price) — $25/1K.
  // Only triggered when a user taps into a venue detail view.
  const details = await fetchGooglePlaceEnterprise(googlePlaceId);
  if (!details) return existing;

  const cachedAt = new Date().toISOString();
  // Merge: keep Basic-tier fields from existing cache, add Enterprise fields
  const venueDetails: CachedVenueDetails = {
    types: existing?.types ?? [],
    primaryType: existing?.primaryType ?? null,
    primaryTypeDisplayName: existing?.primaryTypeDisplayName ?? null,
    rating: details.rating ?? null,
    userRatingCount: details.userRatingCount ?? null,
    priceLevel: details.priceLevel ?? null,
    priceRange: formatPriceRange(details.priceRange),
    reviews: (details.reviews ?? []).map((r) => ({
      authorName: r.authorAttribution?.displayName ?? "Anonymous",
      rating: r.rating ?? 0,
      text: r.text?.text ?? "",
      relativePublishTime: r.relativePublishTimeDescription ?? "",
      publishTime: r.publishTime ?? "",
    })),
    editorialSummary: details.editorialSummary?.text ?? null,
    enterpriseFetched: true,
    cachedAt,
  };

  // Cache for 30 days (overwrites Basic-tier entry with full details)
  const ttl = Math.floor(Date.now() / 1000) + DATA_TTL_DAYS * 86_400;
  await putItem({
    PK: venueKey(venueId),
    SK: GDETAILS_SK,
    ...venueDetails,
    ttl,
  });

  log.debug("Backfilled venue details (Enterprise)", { venueId });
  return venueDetails;
}

/**
 * Read cached venue details (categories, rating, reviews, price) from DynamoDB.
 * Pure cache reader — never triggers Google API calls. Details are populated
 * as a side effect of getGoogleHoursData() when it fetches from the API.
 */
export async function getGoogleVenueDetails(venueId: string): Promise<CachedVenueDetails | null> {
  const cached = await getItem(venueKey(venueId), GDETAILS_SK);
  if (!cached) return null;

  const ttl = cached.ttl as number | undefined;
  if (ttl && ttl < Math.floor(Date.now() / 1000)) return null;

  return {
    types: (cached.types as string[]) ?? [],
    primaryType: (cached.primaryType as string) ?? null,
    primaryTypeDisplayName: (cached.primaryTypeDisplayName as string) ?? null,
    rating: (cached.rating as number) ?? null,
    userRatingCount: (cached.userRatingCount as number) ?? null,
    priceLevel: (cached.priceLevel as string) ?? null,
    priceRange: (cached.priceRange as string) ?? null,
    reviews: (cached.reviews as CachedVenueDetails["reviews"]) ?? [],
    editorialSummary: (cached.editorialSummary as string) ?? null,
    enterpriseFetched: (cached.enterpriseFetched as boolean) ?? false,
    cachedAt: cached.cachedAt as string,
  };
}

/**
 * Determine if a venue is currently open based on cached Google hours.
 * Returns open status and contextual hours string like Apple/Google Maps:
 * - "Open · Closes 10:00 PM"
 * - "Closed · Opens 11:00 AM"
 * - "Open 24 hours"
 */
export function isOpenNow(
  data: CachedGoogleHours,
  nowMs: number,
  timezone: string
): OpenStatus {
  // Permanently or temporarily closed venues
  if (data.businessStatus === "CLOSED_PERMANENTLY") {
    return { isOpen: false, hoursToday: "Permanently closed" };
  }
  if (data.businessStatus === "CLOSED_TEMPORARILY") {
    return { isOpen: false, hoursToday: "Temporarily closed" };
  }

  // No periods data — can't determine
  if (data.regularPeriods.length === 0) {
    return { isOpen: false, hoursToday: null };
  }

  // Check if a 24-hour venue
  if (is24Hours(data.regularPeriods)) {
    return { isOpen: true, hoursToday: "Open 24 hours" };
  }

  const { localDay, localMinutes } = getLocalTime(nowMs, timezone);
  const currentTotalMinutes = localDay * 24 * 60 + localMinutes;

  // Check if current time falls within any open period, and track which one
  let isOpen = false;
  let currentCloseTime: { hour: number; minute: number } | null = null;

  for (const period of data.regularPeriods) {
    const openTotal = period.openDay * 24 * 60 + period.openHour * 60 + period.openMinute;
    let closeTotal = period.closeDay * 24 * 60 + period.closeHour * 60 + period.closeMinute;

    if (closeTotal <= openTotal) {
      closeTotal += 7 * 24 * 60;
    }

    let checkTime = currentTotalMinutes;
    if (checkTime < openTotal) {
      checkTime += 7 * 24 * 60;
    }

    if (checkTime >= openTotal && checkTime < closeTotal) {
      isOpen = true;
      currentCloseTime = { hour: period.closeHour, minute: period.closeMinute };
      break;
    }
  }

  let hoursToday: string;

  if (isOpen && currentCloseTime) {
    // "Closes 10:00 PM"
    hoursToday = `Closes ${formatTime(currentCloseTime.hour, currentCloseTime.minute)}`;
  } else if (!isOpen) {
    // Find the next opening time
    const nextOpen = findNextOpenTime(data.regularPeriods, localDay, localMinutes);
    if (nextOpen) {
      hoursToday = `Opens ${nextOpen}`;
    } else {
      hoursToday = "Closed today";
    }
  } else {
    hoursToday = formatTodayHours(data.regularPeriods, localDay) ?? "Open";
  }

  return { isOpen, hoursToday };
}

// -----------------------------------------------
// Venue matching
// -----------------------------------------------

/** Sentinel value stored as googlePlaceId when matching fails. */
const NO_MATCH_SENTINEL = "__NO_MATCH__";

/** Check for a cached Google Place ID mapping.
 * Returns the place ID, NO_MATCH_SENTINEL for cached failures, or null for cache miss. */
async function getCachedGoogleMapping(venueId: string): Promise<string | null> {
  const item = await getItem(venueKey(venueId), mappingSK("google"));
  if (!item) return null;

  const ttl = item.ttl as number | undefined;
  if (ttl && ttl < Math.floor(Date.now() / 1000)) return null;

  return (item.googlePlaceId as string) ?? null;
}

/**
 * Match a venue to a Google Place ID using Text Search.
 * Single call with location-qualified query ("name near lat,lng") for best
 * accuracy. Proximity bonus for venues within 50m handles minor name
 * differences (e.g., "Unholy Donuts" vs "Unholy Donut").
 */
async function matchGoogleVenue(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number,
  address?: string
): Promise<string | null> {
  const log = createLogger("google:match");

  // When address is available, use it in the query for more reliable matching
  // (MapKit coordinates can be significantly off, but addresses are usually correct).
  // Fall back to coordinate-based query when no address is provided.
  const textQuery = address
    ? `${venueName} ${address}`
    : `${venueName} near ${lat.toFixed(4)},${lng.toFixed(4)}`;

  const body = {
    textQuery,
    locationBias: {
      circle: {
        center: { latitude: lat, longitude: lng },
        radius: MATCH_MAX_DISTANCE_M,
      },
    },
    maxResultCount: 5,
  };

  const response = await googleFetchWithRetry(
    `${GOOGLE_BASE}/places:searchText`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": GOOGLE_API_KEY,
        "X-Goog-FieldMask": "places.id,places.displayName,places.location",
      },
      body: JSON.stringify(body),
    },
    `match:${venueId}`
  );

  if (!response) return null;

  const data = (await response.json()) as GoogleSearchResult;
  const candidates = data.places ?? [];
  if (candidates.length === 0) {
    log.debug("No Google candidates returned", { venueId, venueName });
    return null;
  }

  // Score candidates — compare against original venueName (not the location-qualified query)
  // When address is provided, relax the distance cap: MapKit coordinates can be
  // several km off while the address is correct, so use 5 km to avoid rejecting
  // valid matches that the address-based query found correctly.
  const maxDistance = address ? 5_000 : MATCH_MAX_DISTANCE_M;
  let bestCandidate: (typeof candidates)[0] | null = null;
  let bestScore = -1;

  for (const candidate of candidates) {
    const candidateName = candidate.displayName?.text ?? "";
    const candidateLat = candidate.location?.latitude;
    const candidateLng = candidate.location?.longitude;

    if (candidateLat == null || candidateLng == null) continue;

    const distance = haversineDistance(lat, lng, candidateLat, candidateLng);
    if (distance > maxDistance) continue;

    const distanceScore = Math.max(0, 1.0 - distance / maxDistance);
    const nameScore = nameSimilarity(venueName, candidateName);

    // Proximity bonus: venues within 50m are very likely the correct match
    // even if name similarity is low (abbreviations, transliterations, etc.)
    const proximityBonus = distance < 50 ? 0.15 : 0;
    const score = 0.4 * distanceScore + 0.6 * nameScore + proximityBonus;

    if (score > bestScore) {
      bestScore = score;
      bestCandidate = candidate;
    }
  }

  if (!bestCandidate || bestScore < MATCH_MIN_SCORE) {
    log.debug("No Google match passed threshold", {
      venueId,
      venueName,
      candidateCount: candidates.length,
      bestScore: bestScore.toFixed(3),
    });
    return null;
  }

  const googlePlaceId = bestCandidate.id;
  log.debug("Matched Google venue", {
    venueId,
    venueName,
    googleName: bestCandidate.displayName?.text,
    score: bestScore.toFixed(3),
  });

  // Cache the mapping for 30 days
  const now = Math.floor(Date.now() / 1000);
  await putItem({
    PK: venueKey(venueId),
    SK: mappingSK("google"),
    googlePlaceId,
    googleName: bestCandidate.displayName?.text ?? "",
    matchScore: bestScore,
    cachedAt: new Date().toISOString(),
    ttl: now + MAPPING_TTL_DAYS * 86_400,
  });

  return googlePlaceId;
}

// -----------------------------------------------
// Google Places API helpers
// -----------------------------------------------

/** Per-request timeout in milliseconds. */
const FETCH_TIMEOUT_MS = 4_000;

/** Fetch with retry, exponential backoff, circuit breaker, and per-request timeout. */
async function googleFetchWithRetry(
  url: string,
  options: RequestInit,
  label: string,
  maxRetries = 2
): Promise<Response | null> {
  if (!googleBreaker.allowRequest()) {
    const log = createLogger("google");
    log.warn("Circuit breaker OPEN — skipping request", { label });
    return null;
  }

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
      const response = await fetch(url, { ...options, signal: controller.signal });
      clearTimeout(timeout);

      if (response.ok) {
        googleBreaker.recordSuccess();
        return response;
      }

      const retryable = response.status === 429 || response.status >= 500;
      if (!retryable || attempt === maxRetries) {
        googleBreaker.recordFailure();
        const log = createLogger("google");
        let body = "(empty)";
        try {
          const raw = await response.text();
          if (raw) body = raw.slice(0, 300);
        } catch { /* ignore */ }
        log.warn("API request failed", {
          label,
          status: response.status,
          attempt: attempt + 1,
          responseBody: body,
        });
        return null;
      }

      // Exponential backoff with jitter: 200-300ms, 400-500ms
      const delayMs = 200 * Math.pow(2, attempt) + Math.random() * 100;
      const log = createLogger("google");
      log.debug("Retrying API request", { label, status: response.status, attempt: attempt + 1, delayMs: Math.round(delayMs) });
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    } catch (err) {
      googleBreaker.recordFailure();
      if (attempt === maxRetries) {
        const log = createLogger("google");
        log.warn("API request error (network/timeout)", {
          label,
          attempt: attempt + 1,
          error: err instanceof Error ? err.message : String(err),
        });
        return null;
      }
      const delayMs = 200 * Math.pow(2, attempt) + Math.random() * 100;
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
  return null;
}

/**
 * Fetch place details — Basic tier only ($5/1K requests).
 * Returns hours, business status, and type classification.
 * Used by getGoogleHoursData() for map/list views where rating/reviews
 * are not needed and the 5× cost difference matters.
 */
async function fetchGooglePlaceBasic(placeId: string): Promise<GooglePlaceDetails | null> {
  const log = createLogger("google:details-basic");

  const response = await googleFetchWithRetry(
    `${GOOGLE_BASE}/places/${placeId}`,
    {
      headers: {
        "X-Goog-Api-Key": GOOGLE_API_KEY,
        "X-Goog-FieldMask": "businessStatus,regularOpeningHours,types,primaryType,primaryTypeDisplayName",
      },
    },
    `details-basic:${placeId}`
  );

  if (!response) return null;

  const data = (await response.json()) as GooglePlaceDetails;
  log.debug("Google Place Details (Basic) fetched", {
    placeId,
    businessStatus: data.businessStatus ?? "unknown",
    periodCount: data.regularOpeningHours?.periods?.length ?? 0,
  });
  return data;
}

/**
 * Fetch place details — Enterprise+Atmosphere tier ($25/1K requests).
 * Returns rating, reviews, price, and editorial summary.
 * Only called from ensureVenueDetails() when a user taps into a
 * single-venue detail view, so the cost is bounded by user interactions.
 */
async function fetchGooglePlaceEnterprise(placeId: string): Promise<GooglePlaceDetails | null> {
  const log = createLogger("google:details-enterprise");

  const response = await googleFetchWithRetry(
    `${GOOGLE_BASE}/places/${placeId}`,
    {
      headers: {
        "X-Goog-Api-Key": GOOGLE_API_KEY,
        "X-Goog-FieldMask": "rating,userRatingCount,priceLevel,priceRange,reviews,editorialSummary",
      },
    },
    `details-enterprise:${placeId}`
  );

  if (!response) return null;

  const data = (await response.json()) as GooglePlaceDetails;
  log.debug("Google Place Details (Enterprise) fetched", {
    placeId,
    rating: data.rating ?? null,
    reviewCount: data.reviews?.length ?? 0,
  });
  return data;
}

// -----------------------------------------------
// Helpers
// -----------------------------------------------

/** Extract a formatted price range string from Google's priceRange object.
 * Returns e.g. "$10–25", "$60+", or null if no data. */
function formatPriceRange(priceRange: GooglePlaceDetails["priceRange"]): string | null {
  if (!priceRange) return null;
  const start = priceRange.startPrice;
  const end = priceRange.endPrice;
  if (!start?.units && !end?.units) return null;

  const currency = start?.currencyCode ?? end?.currencyCode ?? "USD";
  const symbol = currencySymbol(currency);
  const startVal = start?.units ? parseInt(start.units, 10) : NaN;
  const endVal = end?.units ? parseInt(end.units, 10) : NaN;

  if (!isNaN(startVal) && !isNaN(endVal)) return `${symbol}${startVal}–${endVal}`;
  if (!isNaN(startVal)) return `${symbol}${startVal}+`;
  if (!isNaN(endVal)) return `Up to ${symbol}${endVal}`;
  return null;
}

function currencySymbol(code: string): string {
  switch (code) {
    case "USD": case "CAD": case "AUD": return "$";
    case "EUR": return "€";
    case "GBP": return "£";
    case "JPY": return "¥";
    default: return `${code} `;
  }
}

function normalizeBusinessStatus(status: string | undefined): CachedGoogleHours["businessStatus"] {
  switch (status) {
    case "OPERATIONAL": return "OPERATIONAL";
    case "CLOSED_TEMPORARILY": return "CLOSED_TEMPORARILY";
    case "CLOSED_PERMANENTLY": return "CLOSED_PERMANENTLY";
    default: return null;
  }
}

/** Check if periods represent a 24-hour venue. */
function is24Hours(periods: GoogleOpenPeriod[]): boolean {
  if (periods.length !== 1) return false;
  const p = periods[0];
  return p.openHour === 0 && p.openMinute === 0 && p.closeHour === 23 && p.closeMinute === 59;
}

/** Format today's opening hours for display (e.g., "11:00 AM – 10:00 PM"). */
function formatTodayHours(periods: GoogleOpenPeriod[], localDay: number): string | null {
  // Find all periods that open on today (Google day convention: 0=Sunday)
  const todayPeriods = periods.filter((p) => p.openDay === localDay);

  // Also include overnight periods from yesterday that extend into today
  const yesterday = (localDay + 6) % 7;
  const overnightPeriods = periods.filter(
    (p) => p.openDay === yesterday && p.closeDay === localDay
  );

  const allPeriods = [...overnightPeriods, ...todayPeriods];
  if (allPeriods.length === 0) return "Closed";

  // Format each period (overnight periods show only closing time)
  const formatted = allPeriods.map((p) => {
    if (p.openDay !== localDay) {
      const close = formatTime(p.closeHour, p.closeMinute);
      return `Closes ${close}`;
    }
    const open = formatTime(p.openHour, p.openMinute);
    const close = formatTime(p.closeHour, p.closeMinute);
    return `${open} – ${close}`;
  });

  return formatted.join(", ");
}

/**
 * Find the next opening time relative to current day+time.
 * Returns a contextual string like "11:00 AM" (if today) or "11:00 AM Mon" (if another day).
 */
function findNextOpenTime(
  periods: GoogleOpenPeriod[],
  currentDay: number,
  currentMinutes: number
): string | null {
  const DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

  // Build a sorted list of all opening times as total-minutes-from-week-start
  const currentTotal = currentDay * 24 * 60 + currentMinutes;

  let bestDelta = Infinity;
  let bestPeriod: GoogleOpenPeriod | null = null;

  for (const p of periods) {
    let openTotal = p.openDay * 24 * 60 + p.openHour * 60 + p.openMinute;

    // How far in the future is this opening?
    let delta = openTotal - currentTotal;
    if (delta <= 0) delta += 7 * 24 * 60; // wrap to next week

    if (delta < bestDelta) {
      bestDelta = delta;
      bestPeriod = p;
    }
  }

  if (!bestPeriod) return null;

  const time = formatTime(bestPeriod.openHour, bestPeriod.openMinute);

  // If it opens later today, just show the time
  if (bestPeriod.openDay === currentDay && bestPeriod.openHour * 60 + bestPeriod.openMinute > currentMinutes) {
    return time;
  }

  // Put the day name first so it's not missed
  return `${DAY_NAMES[bestPeriod.openDay]} at ${time}`;
}

/** Format hour:minute as "11:00 AM" style. */
function formatTime(hour: number, minute: number): string {
  const period = hour >= 12 ? "PM" : "AM";
  const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
  const displayMinute = minute.toString().padStart(2, "0");
  return `${displayHour}:${displayMinute} ${period}`;
}
