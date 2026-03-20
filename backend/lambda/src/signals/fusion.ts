import { VenueSignal, FusedEstimate, ConfidenceLevel } from "./types";

/** Threshold: sources diverging by more than this are in conflict. */
const CONFLICT_THRESHOLD = 0.3;
/** Bonus multiplier when 3+ sources agree within this range. */
const CORROBORATION_RANGE = 0.15;
const CORROBORATION_BONUS = 1.3;
/** Penalty multiplier for outlier signals during conflict. */
const OUTLIER_PENALTY = 0.5;

/**
 * Fuse multiple venue signals into a single busyness estimate.
 *
 * Algorithm:
 * 1. Compute effective weight for each signal: baseWeight × freshnessDecay × confidence
 * 2. Detect conflict: if max(scores) - min(scores) > 0.3, flag and penalize outliers
 * 3. Apply corroboration bonus: if 3+ signals agree within 0.15, boost their weights by 1.3×
 * 4. Weighted average to produce final score
 * 5. Map to confidence level based on source count and agreement
 */
export function fuseSignals(signals: VenueSignal[], now = Date.now()): FusedEstimate {
  if (signals.length === 0) {
    return emptyEstimate("");
  }

  const venueId = signals[0].venueId;

  // Step 1: Compute effective weights with freshness decay
  const weighted = signals.map((s) => {
    const ageMinutes = (now - s.timestamp) / 60_000;
    const halfLifeMinutes = s.ttlSeconds / 60;
    const freshness = Math.exp(-ageMinutes / halfLifeMinutes);
    const effectiveWeight = s.baseWeight * freshness * s.confidence;
    return { signal: s, effectiveWeight };
  });

  // Step 2: Conflict detection
  const scores = weighted.map((w) => w.signal.busynessScore);
  const minScore = Math.min(...scores);
  const maxScore = Math.max(...scores);
  const conflictDetected = scores.length >= 2 && (maxScore - minScore) > CONFLICT_THRESHOLD;

  // During conflict, penalize outliers (furthest from median)
  if (conflictDetected) {
    const sorted = [...scores].sort((a, b) => a - b);
    const median = sorted[Math.floor(sorted.length / 2)];

    for (const w of weighted) {
      const distance = Math.abs(w.signal.busynessScore - median);
      // If this signal is the outlier (furthest from median), reduce its weight
      if (distance > CONFLICT_THRESHOLD / 2) {
        w.effectiveWeight *= OUTLIER_PENALTY;
      }
    }
  }

  // Step 3: Corroboration bonus (future-ready for 3+ sources)
  if (weighted.length >= 3) {
    // Group signals that agree within the corroboration range
    for (let i = 0; i < weighted.length; i++) {
      let agreeing = 0;
      for (let j = 0; j < weighted.length; j++) {
        if (i === j) continue;
        if (Math.abs(weighted[i].signal.busynessScore - weighted[j].signal.busynessScore) <= CORROBORATION_RANGE) {
          agreeing++;
        }
      }
      // If 2+ other signals agree with this one (total 3+), apply bonus
      if (agreeing >= 2) {
        weighted[i].effectiveWeight *= CORROBORATION_BONUS;
      }
    }
  }

  // Step 4: Weighted average
  let totalWeight = 0;
  let weightedSum = 0;
  for (const w of weighted) {
    weightedSum += w.signal.busynessScore * w.effectiveWeight;
    totalWeight += w.effectiveWeight;
  }

  const busynessScore = totalWeight > 0 ? weightedSum / totalWeight : 0.5;

  // Extract report-specific data
  const reportSignal = signals.find((s) => s.sourceId === "user_reports");
  const reportCount = reportSignal?.reportCount ?? 0;
  const waitMinutes = reportSignal?.waitMinutes ?? null;

  // Step 5: Confidence mapping
  const confidence = computeConfidence(weighted, conflictDetected);

  return {
    venueId,
    busynessScore: Math.round(busynessScore * 1000) / 1000, // 3 decimal places
    confidence,
    reportCount,
    waitMinutes,
    sourceCount: signals.length,
    sources: signals.map((s) => s.sourceId),
    conflictDetected,
    computedAt: new Date(now).toISOString(),
  };
}

/**
 * Determine the overall confidence level based on source count,
 * signal quality, and agreement.
 */
function computeConfidence(
  weighted: Array<{ signal: VenueSignal; effectiveWeight: number }>,
  conflictDetected: boolean
): ConfidenceLevel {
  const sourceCount = weighted.length;
  const totalEffectiveWeight = weighted.reduce((sum, w) => sum + w.effectiveWeight, 0);

  if (sourceCount === 0) return "ESTIMATED";

  // VERY_HIGH: 3+ sources agreeing (no conflict), strong total weight
  if (sourceCount >= 3 && !conflictDetected && totalEffectiveWeight > 1.0) {
    return "VERY_HIGH";
  }

  // HIGH: 2+ sources with good agreement, or strong individual signals
  if (sourceCount >= 2 && !conflictDetected) {
    return "HIGH";
  }

  // MEDIUM: 1 source with decent confidence, or 2+ with conflict
  if (sourceCount >= 2 && conflictDetected) {
    return "MEDIUM";
  }

  // Single source: depends on quality
  const single = weighted[0];
  if (single.signal.sourceId === "user_reports" && (single.signal.reportCount ?? 0) >= 3) {
    return "MEDIUM";
  }
  if (single.signal.sourceId === "foursquare" && single.signal.confidence >= 0.6) {
    return "MEDIUM";
  }

  return "LOW";
}

/** Produce an empty/default estimate when no signals are available. */
export function emptyEstimate(venueId: string): FusedEstimate {
  return {
    venueId,
    busynessScore: 0.5,
    confidence: "ESTIMATED",
    reportCount: 0,
    waitMinutes: null,
    sourceCount: 0,
    sources: [],
    conflictDetected: false,
    computedAt: new Date().toISOString(),
  };
}
