// -----------------------------------------------
// Signal types for the Wayt Fusion Engine
// -----------------------------------------------

/** A single busyness signal from one data source. */
export interface VenueSignal {
  /** Source identifier. */
  sourceId: SignalSource;
  /** Venue identifier (matches iOS venue ID format). */
  venueId: string;
  /** Normalized busyness score: 0.0 (empty) to 1.0 (packed). */
  busynessScore: number;
  /** Source-specific confidence: 0.0 to 1.0. */
  confidence: number;
  /** Base weight for this source type (before freshness decay). */
  baseWeight: number;
  /** When this signal was captured (epoch ms). */
  timestamp: number;
  /** How long this signal stays valid (seconds). */
  ttlSeconds: number;
  /** Optional: report count (only for user_reports source). */
  reportCount?: number;
  /** Optional: average wait in minutes (only for user_reports source). */
  waitMinutes?: number;
}

/** The fused result combining all available signals for a venue. */
export interface FusedEstimate {
  venueId: string;
  /** Normalized busyness: 0.0 to 1.0. */
  busynessScore: number;
  /** Overall confidence level. */
  confidence: ConfidenceLevel;
  /** Number of user reports contributing to the estimate. */
  reportCount: number;
  /** Estimated wait in minutes (from user reports, if available). */
  waitMinutes: number | null;
  /** How many distinct sources contributed. */
  sourceCount: number;
  /** List of source IDs that contributed. */
  sources: string[];
  /** True if sources significantly disagree (max-min > 0.3). */
  conflictDetected: boolean;
  /** ISO timestamp of when this estimate was computed. */
  computedAt: string;
  /** Suggested client-side refresh interval in seconds. Lower = more active venue. */
  refreshAfterSeconds: number;
  /** Whether the venue is currently open (from Google Places hours). null = unknown. */
  isOpen?: boolean | null;
  /** Today's operating hours for display (e.g. "11:00 AM – 10:00 PM"). null = unknown. */
  hoursToday?: string | null;
  /** Google Places business status. null = unknown or not yet resolved. */
  businessStatus?: "OPERATIONAL" | "CLOSED_TEMPORARILY" | "CLOSED_PERMANENTLY" | null;
  /** Lightweight venue details (categories, rating, price). Null if not yet fetched. */
  venueDetails?: VenueDetailsSummary | null;
}

// -----------------------------------------------
// Enums & constants
// -----------------------------------------------

export type SignalSource = "foursquare" | "user_reports";

export type ConfidenceLevel = "VERY_HIGH" | "HIGH" | "MEDIUM" | "LOW" | "ESTIMATED";

/** Per-source configuration: base weight and cache TTL. */
export const SOURCE_CONFIG: Record<SignalSource, { weight: number; ttlSeconds: number }> = {
  user_reports: { weight: 0.75, ttlSeconds: 7_200 },   // 2 hours
  foursquare:   { weight: 0.25, ttlSeconds: 300 },     // 5 min (score recomputed from 30-day cached data)
};

// -----------------------------------------------
// Google venue details (categories, ratings, reviews)
// -----------------------------------------------

/** A single Google review cached from Place Details. */
export interface GoogleReview {
  authorName: string;
  rating: number;              // 1-5
  text: string;
  relativePublishTime: string; // e.g. "2 months ago"
  publishTime: string;         // ISO timestamp
}

/** Cached Google venue details stored in DynamoDB (SK: GDETAILS#CURRENT). */
export interface CachedVenueDetails {
  types: string[];
  primaryType: string | null;
  primaryTypeDisplayName: string | null;
  rating: number | null;              // 1.0-5.0 (Google scale)
  userRatingCount: number | null;
  priceLevel: string | null;          // e.g. "PRICE_LEVEL_MODERATE"
  priceRange: string | null;          // e.g. "$10–25" (formatted from Google priceRange)
  reviews: GoogleReview[];
  editorialSummary: string | null;
  /** True when Enterprise-tier fields (rating, reviews, price) have been fetched.
   *  Distinguishes Basic-tier-only entries from venues that genuinely have no rating. */
  enterpriseFetched?: boolean;
  cachedAt: string;
}

/** Lightweight venue details included in list responses. */
export interface VenueDetailsSummary {
  primaryType: string | null;
  primaryTypeDisplayName: string | null;
  rating: number | null;
  userRatingCount: number | null;
  priceLevel: string | null;
  priceRange: string | null;
}

/** Full venue details included in single-venue responses. */
export interface VenueDetailsFull extends VenueDetailsSummary {
  types: string[];
  reviews: GoogleReview[];
  editorialSummary: string | null;
  googleMapsUrl: string | null;
}

// -----------------------------------------------
// Venue category (for busyness curve shaping)
// -----------------------------------------------

/** Behavioral category that controls temporal curve shape and day-of-week multipliers. */
export type VenueCategory = "restaurant" | "bar" | "coffee" | "nightclub" | "default";

/**
 * Map a Google Places `primaryType` string to a VenueCategory for busyness modelling.
 * Reference: https://developers.google.com/maps/documentation/places/web-service/place-types
 *
 * Uses exact match or boundary-safe checks to avoid false positives like
 * "barbecue_restaurant" matching "bar".
 */
export function classifyVenueCategory(primaryType: string | null | undefined): VenueCategory {
  if (!primaryType) return "default";
  const t = primaryType.toLowerCase();

  // Coffee shops, cafés, bakeries, tea houses
  if (t.includes("cafe") || t.includes("coffee") || t.includes("tea_house") || t.includes("bakery")) {
    return "coffee";
  }
  // Nightclubs, dance clubs, karaoke
  if (t.includes("night_club") || t.includes("disco") || t === "karaoke") {
    return "nightclub";
  }
  // Bars, pubs, breweries — boundary-safe to avoid matching "barbecue_restaurant"
  // Google bar types: bar, bar_and_grill, cocktail_bar, lounge_bar, sports_bar, wine_bar
  if (t === "bar" || t.endsWith("_bar") || t.startsWith("bar_") || t.includes("pub") || t.includes("brewery")) {
    return "bar";
  }
  // Restaurants (broad catch-all for dining)
  if (
    t.includes("restaurant") || t.includes("meal") || t.includes("steak") ||
    t.includes("pizza") || t.includes("sushi") || t.includes("ramen") ||
    t.includes("seafood") || t.includes("bbq") || t.includes("diner") ||
    t.includes("bistro") || t.includes("fast_food")
  ) {
    return "restaurant";
  }
  return "default";
}

// -----------------------------------------------
// Helpers
// -----------------------------------------------

/** Convert a 1-5 busyness level to 0.0-1.0 normalized score. */
export function normalizeLevel(level: number): number {
  return Math.max(0, Math.min(1, (level - 1) / 4));
}

/** Convert a 0.0-1.0 normalized score back to 1-5 level. */
export function denormalizeScore(score: number): number {
  return Math.max(1, Math.min(5, score * 4 + 1));
}
