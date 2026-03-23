/**
 * Google Places API integration for accurate operating hours.
 *
 * Supplements Foursquare (busyness signals) with Google's regularOpeningHours
 * to provide reliable open/closed status. Foursquare's hours_popular represents
 * peak times, not operating hours — Google fills this gap.
 *
 * Caching strategy: 30-day TTL on both venue mapping and hours data.
 * At $20/1K Place Details requests (Enterprise tier), this keeps costs
 * to ~$0.02/venue/month.
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

const GOOGLE_API_KEY = process.env.GOOGLE_PLACES_API_KEY ?? "";
const GOOGLE_BASE = "https://places.googleapis.com/v1";
const MAPPING_TTL_DAYS = 30;
const DATA_TTL_DAYS = 30;

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

interface GooglePlaceDetails {
  businessStatus?: string;
  regularOpeningHours?: {
    periods?: Array<{
      open: { day: number; hour: number; minute: number };
      close?: { day: number; hour: number; minute: number };
    }>;
  };
}

// -----------------------------------------------
// Public API
// -----------------------------------------------

const GDATA_SK = "GDATA#CURRENT";

/**
 * Get cached Google hours data for a venue, fetching from API on cache miss.
 * Returns null if no API key, no match found, or venue is permanently closed.
 */
export async function getGoogleHoursData(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number
): Promise<CachedGoogleHours | null> {
  if (!GOOGLE_API_KEY) return null;

  const log = createLogger("google");

  try {
    // Check cache first
    const cached = await getItem(venueKey(venueId), GDATA_SK);
    if (cached) {
      const ttl = cached.ttl as number | undefined;
      if (!ttl || ttl >= Math.floor(Date.now() / 1000)) {
        return {
          businessStatus: (cached.businessStatus as CachedGoogleHours["businessStatus"]) ?? null,
          regularPeriods: (cached.regularPeriods as GoogleOpenPeriod[]) ?? [],
          cachedAt: cached.cachedAt as string,
        };
      }
    }

    // Cache miss — resolve Google Place ID
    const googlePlaceId = await getCachedGoogleMapping(venueId)
      ?? await matchGoogleVenue(venueId, venueName, lat, lng);
    if (!googlePlaceId) return null;

    // Fetch hours from Google Places API
    const details = await fetchGooglePlaceDetails(googlePlaceId);
    if (!details) return null;

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
      cachedAt: new Date().toISOString(),
    };

    // Cache for 30 days
    const nowSeconds = Math.floor(Date.now() / 1000);
    await putItem({
      PK: venueKey(venueId),
      SK: GDATA_SK,
      ...data,
      ttl: nowSeconds + DATA_TTL_DAYS * 86_400,
    });

    return data;
  } catch (err) {
    log.error("Failed to fetch Google hours", { venueId }, err);
    return null;
  }
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

/** Check for a cached Google Place ID mapping. */
async function getCachedGoogleMapping(venueId: string): Promise<string | null> {
  const item = await getItem(venueKey(venueId), mappingSK("google"));
  if (!item) return null;

  const ttl = item.ttl as number | undefined;
  if (ttl && ttl < Math.floor(Date.now() / 1000)) return null;

  return (item.googlePlaceId as string) ?? null;
}

/**
 * Match a venue to a Google Place ID using Text Search.
 * Uses Basic field mask (id, displayName, location) to minimize cost.
 */
async function matchGoogleVenue(
  venueId: string,
  venueName: string,
  lat: number,
  lng: number
): Promise<string | null> {
  const log = createLogger("google:match");

  const body = {
    textQuery: venueName,
    locationBias: {
      circle: {
        center: { latitude: lat, longitude: lng },
        radius: MATCH_MAX_DISTANCE_M,
      },
    },
    maxResultCount: 5,
  };

  const response = await fetch(`${GOOGLE_BASE}/places:searchText`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": GOOGLE_API_KEY,
      "X-Goog-FieldMask": "places.id,places.displayName,places.location",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    log.warn("Google Text Search failed", { status: response.status, venueName });
    return null;
  }

  const data = (await response.json()) as GoogleSearchResult;
  const candidates = data.places ?? [];
  if (candidates.length === 0) return null;

  // Score candidates using shared matching logic
  let bestCandidate: (typeof candidates)[0] | null = null;
  let bestScore = -1;

  for (const candidate of candidates) {
    const candidateName = candidate.displayName?.text ?? "";
    const candidateLat = candidate.location?.latitude;
    const candidateLng = candidate.location?.longitude;

    if (candidateLat == null || candidateLng == null) continue;

    const distance = haversineDistance(lat, lng, candidateLat, candidateLng);
    if (distance > MATCH_MAX_DISTANCE_M) continue;

    const distanceScore = Math.max(0, 1.0 - distance / MATCH_MAX_DISTANCE_M);
    const nameScore = nameSimilarity(venueName, candidateName);
    const score = 0.4 * distanceScore + 0.6 * nameScore;

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

/**
 * Fetch place details from Google Places API (New).
 * Requests only regularOpeningHours and businessStatus (Enterprise tier).
 */
async function fetchGooglePlaceDetails(placeId: string): Promise<GooglePlaceDetails | null> {
  const log = createLogger("google:details");

  const response = await fetch(`${GOOGLE_BASE}/places/${placeId}`, {
    headers: {
      "X-Goog-Api-Key": GOOGLE_API_KEY,
      "X-Goog-FieldMask": "businessStatus,regularOpeningHours",
    },
  });

  if (!response.ok) {
    log.warn("Google Place Details failed", { placeId, status: response.status });
    return null;
  }

  return (await response.json()) as GooglePlaceDetails;
}

// -----------------------------------------------
// Helpers
// -----------------------------------------------

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

  // Format each period
  const formatted = todayPeriods.map((p) => {
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
