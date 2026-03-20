// -----------------------------------------------
// Signal types for the Venuu Fusion Engine
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
}

// -----------------------------------------------
// Enums & constants
// -----------------------------------------------

export type SignalSource = "foursquare" | "user_reports";

export type ConfidenceLevel = "VERY_HIGH" | "HIGH" | "MEDIUM" | "LOW" | "ESTIMATED";

/** Per-source configuration: base weight and cache TTL. */
export const SOURCE_CONFIG: Record<SignalSource, { weight: number; ttlSeconds: number }> = {
  user_reports: { weight: 0.75, ttlSeconds: 7_200 },   // 2 hours
  foursquare:   { weight: 0.25, ttlSeconds: 600 },     // 10 min (score recomputed from 30-day cached data)
};

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
