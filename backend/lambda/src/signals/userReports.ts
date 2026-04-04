import { BatchGetCommand, GetCommand, QueryCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { ddb, REPORTS_TABLE, venueKey, getItem, putItem } from "../db";
import { VenueSignal, SOURCE_CONFIG, normalizeLevel, classifyVenueCategory, mapClientCategory } from "./types";
import { CachedFsqData, computeTimeAwareBusyness } from "./foursquare";
import {
  USERS_TABLE,
  DEFAULT_TRUST_SCORE,
  NEW_ACCOUNT_TRUST_SCORE,
  NEW_ACCOUNT_THRESHOLD_MS,
  TRUST_CORROBORATION_REWARD,
  TRUST_OUTLIER_PENALTY,
  TRUST_FLOOR,
  TRUST_CAP,
} from "../shared";
import { createLogger } from "../logger";

/** How far back to look for reports (2 hours, matching the DynamoDB TTL). */
const MAX_AGE_MS = 2 * 60 * 60 * 1000;

/** Default cache TTL for aggregated report signal (5 minutes). */
const AGGREGATION_CACHE_TTL_SECONDS = 5 * 60;
/** Shorter cache TTL for high-activity venues (3+ reports) to support faster client refresh. */
const HIGH_ACTIVITY_CACHE_TTL_SECONDS = 2 * 60;
const REPORT_AGG_SK = "SIGNAL#user_reports_agg";

/** Normalized score difference (0-1 scale) above which a report is considered implausible. ~3 levels on 1-5 scale. */
const PLAUSIBILITY_THRESHOLD = 0.6;
const PLAUSIBILITY_PENALTY = 0.5;
/** Min Foursquare confidence to apply plausibility check — don't penalize against weak predictions. */
const PLAUSIBILITY_MIN_CONFIDENCE = 0.4;

/** True half-life for wait-time decay by venue category (minutes). */
const WAIT_HALF_LIFE: Record<string, number> = {
  coffee: 20,
  restaurant: 35,
  bar: 25,
  nightclub: 30,
  default: 30,
};
const DEFAULT_WAIT_HALF_LIFE = 30;

/**
 * Aggregate user reports from the existing VenueReports table into a single
 * VenueSignal. Uses exponential decay weighting (mirrors the iOS BusynessEngine).
 *
 * Results are cached for 5 minutes in the signals table to avoid re-scanning
 * hundreds of reports on every request for popular venues.
 *
 * Returns null if there are no recent reports for this venue.
 */
export async function aggregateUserReports(venueId: string): Promise<VenueSignal | null> {
  try {
    // Check for cached aggregation first
    const cached = await getItem(venueKey(venueId), REPORT_AGG_SK);
    if (cached) {
      const ttl = cached.ttl as number | undefined;
      if (!ttl || ttl >= Math.floor(Date.now() / 1000)) {
        const log = createLogger("userReports");
        log.debug("Aggregation cache hit", { venueId });
        return {
          sourceId: "user_reports",
          venueId,
          busynessScore: cached.busynessScore as number,
          confidence: cached.confidence as number,
          baseWeight: cached.baseWeight as number,
          timestamp: cached.timestamp as number,
          ttlSeconds: cached.ttlSeconds as number,
          reportCount: cached.reportCount as number,
          waitMinutes: (cached.waitMinutes as number | undefined) ?? undefined,
        };
      }
    }

    const now = Date.now();
    const cutoff = now - MAX_AGE_MS;

    // Query the existing VenueReports table (PK = venueId, SK = timestamp)
    const result = await ddb.send(
      new QueryCommand({
        TableName: REPORTS_TABLE,
        KeyConditionExpression: "venueId = :vid AND #ts > :cutoff",
        ExpressionAttributeNames: { "#ts": "timestamp" },
        ExpressionAttributeValues: {
          ":vid": venueId,
          ":cutoff": cutoff,
        },
        ScanIndexForward: false, // newest first
        Limit: 500,
      })
    );

    const items = result.Items ?? [];
    if (items.length === 0) return null;

    const trustScores = await fetchTrustScores(items, now);

    const venueLng = items[0]?.lng as number | undefined;
    const predictedScore = await getFoursquarePrediction(venueId, now, venueLng);

    // Compute weighted average with exponential decay
    let totalWeight = 0;
    let weightedBusyness = 0;
    let totalWaitWeight = 0;
    let weightedWait = 0;
    let waitCount = 0;
    let latestTimestamp = 0;
    let latestWaitTimestamp = 0;

    for (const item of items) {
      const level = item.busynessLevel as number;
      const ts = item.timestamp as number;
      const userId = item.userId as string;
      const ageMinutes = (now - ts) / 60_000;

      const trust = trustScores.get(userId) ?? DEFAULT_TRUST_SCORE;
      let weight = Math.exp(-ageMinutes / 60) * trust;

      if (predictedScore != null) {
        const normalizedLevel = normalizeLevel(level);
        if (Math.abs(normalizedLevel - predictedScore) > PLAUSIBILITY_THRESHOLD) {
          weight *= PLAUSIBILITY_PENALTY;
        }
      }

      weightedBusyness += level * weight;
      totalWeight += weight;
      latestTimestamp = Math.max(latestTimestamp, ts);

      if (item.waitMinutes != null) {
        weightedWait += (item.waitMinutes as number) * weight;
        totalWaitWeight += weight;
        waitCount++;
        latestWaitTimestamp = Math.max(latestWaitTimestamp, ts);
      }
    }

    if (totalWeight === 0) return null;

    const avgBusyness = weightedBusyness / totalWeight; // 1.0-5.0 scale
    let avgWait: number | undefined = totalWaitWeight > 0 ? Math.round(weightedWait / totalWaitWeight) : undefined;

    // Decay wait time; floor at 2 min to suppress stale "1 min" noise.
    if (avgWait != null && latestWaitTimestamp > 0) {
      const waitAge = (now - latestWaitTimestamp) / 60_000;

      // Majority-vote venueType across all reports (guards against a single misclassified report)
      const typeCounts = new Map<string, number>();
      for (const item of items) {
        const vt = (item.venueType as string) ?? "";
        typeCounts.set(vt, (typeCounts.get(vt) ?? 0) + 1);
      }
      let venueType = "";
      let maxCount = 0;
      for (const [vt, count] of typeCounts) {
        if (count > maxCount) { venueType = vt; maxCount = count; }
      }

      const halfLife = WAIT_HALF_LIFE[mapClientCategory(venueType)] ?? DEFAULT_WAIT_HALF_LIFE;
      const decayed = Math.round(avgWait * Math.exp(-waitAge * Math.LN2 / halfLife));
      avgWait = decayed >= 2 ? decayed : undefined;
    }

    const config = SOURCE_CONFIG.user_reports;
    const reportCount = items.length;

    // Confidence: higher with more reports
    const confidence = reportCount >= 3 ? 0.9 : reportCount >= 2 ? 0.7 : 0.4;

    const signal: VenueSignal = {
      sourceId: "user_reports",
      venueId,
      busynessScore: normalizeLevel(avgBusyness),
      confidence,
      baseWeight: config.weight,
      timestamp: latestTimestamp,
      ttlSeconds: config.ttlSeconds,
      reportCount,
      waitMinutes: avgWait,
    };

    const cacheTtl = reportCount >= 3 ? HIGH_ACTIVITY_CACHE_TTL_SECONDS : AGGREGATION_CACHE_TTL_SECONDS;
    const nowSeconds = Math.floor(now / 1000);
    await putItem({
      PK: venueKey(venueId),
      SK: REPORT_AGG_SK,
      ...signal,
      ttl: nowSeconds + cacheTtl,
    }).catch(() => {
      // Non-critical: if cache write fails, next request will re-aggregate
    });

    // Fire-and-forget — don't block the aggregation response
    if (reportCount >= 2) {
      updateTrustScores(venueId, items, now).catch(() => {});
    }

    return signal;
  } catch (err) {
    const log = createLogger("userReports");
    log.error("Failed to aggregate reports", { venueId }, err);
    return null;
  }
}

// -----------------------------------------------
// Plausibility Helper
// -----------------------------------------------

async function getFoursquarePrediction(venueId: string, now: number, venueLng?: number): Promise<number | null> {
  try {
    const [fsqRaw, detailsRaw] = await Promise.all([
      getItem(venueKey(venueId), "FSQDATA#CURRENT"),
      getItem(venueKey(venueId), "GDETAILS#CURRENT"),
    ]);
    if (!fsqRaw) return null;

    const data: CachedFsqData = {
      popularity: (fsqRaw.popularity as number | null) ?? null,
      rating: (fsqRaw.rating as number | null) ?? null,
      hoursPopular: (fsqRaw.hoursPopular as CachedFsqData["hoursPopular"]) ?? [],
    };
    // Estimate timezone from longitude (±1hr, no DST — better than hardcoded UTC)
    const offsetHours = venueLng != null ? Math.round(-venueLng / 15) : 0;
    const tz = offsetHours === 0 ? "UTC" : `Etc/GMT${offsetHours > 0 ? "+" : ""}${offsetHours}`;
    const category = classifyVenueCategory(detailsRaw?.primaryType as string | null);
    const { score, confidence } = computeTimeAwareBusyness(data, now, tz, undefined, category);
    return confidence >= PLAUSIBILITY_MIN_CONFIDENCE ? score : null;
  } catch {
    return null;
  }
}

// -----------------------------------------------
// Trust Score Helpers
// -----------------------------------------------

async function fetchTrustScores(
  items: Record<string, unknown>[],
  now: number
): Promise<Map<string, number>> {
  const userIds = [...new Set(items.map((i) => i.userId as string))];
  const scores = new Map<string, number>();
  if (userIds.length === 0) return scores;

  // BatchGetItem supports max 100 keys per call
  for (let i = 0; i < userIds.length; i += 100) {
    const batch = userIds.slice(i, i + 100);
    try {
      let response = await ddb.send(
        new BatchGetCommand({
          RequestItems: {
            [USERS_TABLE]: { Keys: batch.map((id) => ({ userId: id })) },
          },
        })
      );
      const processItems = (responseItems: Record<string, unknown>[]) => {
        for (const item of responseItems) {
          const userId = item.userId as string;
          const joinedAt = item.joinedAt as string | undefined;
          const isNewAccount = joinedAt && (now - new Date(joinedAt).getTime()) < NEW_ACCOUNT_THRESHOLD_MS;
          const trust = (item.trustScore as number | undefined)
            ?? (isNewAccount ? NEW_ACCOUNT_TRUST_SCORE : DEFAULT_TRUST_SCORE);
          scores.set(userId, trust);
        }
      };
      processItems(response.Responses?.[USERS_TABLE] ?? []);

      let unprocessed = response.UnprocessedKeys?.[USERS_TABLE];
      while (unprocessed?.Keys?.length) {
        response = await ddb.send(new BatchGetCommand({ RequestItems: { [USERS_TABLE]: unprocessed } }));
        processItems(response.Responses?.[USERS_TABLE] ?? []);
        unprocessed = response.UnprocessedKeys?.[USERS_TABLE];
      }
    } catch {
      // On failure, missing users fall through to DEFAULT_TRUST_SCORE via the ?? in the caller
    }
  }
  return scores;
}

const TRUST_UPDATE_SK_PREFIX = "TRUST_UPDATE#";
/** TTL for idempotency markers — matches report TTL (2 hours). */
const TRUST_MARKER_TTL_SECONDS = 2 * 60 * 60;
const CORROBORATION_WINDOW_MS = 60 * 60 * 1000;
const RECENT_LEVELS_SIZE = 10;
const VARIANCE_PENALTY = 0.01;
/** Max busyness level difference for corroboration (on 1-5 scale). */
const CORROBORATION_LEVEL_RANGE = 0.5;
/** Min busyness level difference for outlier detection (on 1-5 scale). */
const OUTLIER_LEVEL_RANGE = 1.5;

/** Idempotent: TTL markers in signals table prevent re-applying per venue window. */
async function updateTrustScores(
  venueId: string,
  items: Record<string, unknown>[],
  now: number
): Promise<void> {
  const log = createLogger("userReports");

  const recentItems = items.filter((i) => (now - (i.timestamp as number)) < CORROBORATION_WINDOW_MS);
  if (recentItems.length < 2) return;

  const updates: { userId: string; delta: number }[] = [];

  for (const item of recentItems) {
    const userId = item.userId as string;
    const level = item.busynessLevel as number;
    const others = recentItems.filter((o) => (o.userId as string) !== userId);

    const agreeing = others.filter((o) => Math.abs((o.busynessLevel as number) - level) <= CORROBORATION_LEVEL_RANGE);
    const disagreeing = others.filter((o) => Math.abs((o.busynessLevel as number) - level) > OUTLIER_LEVEL_RANGE);

    if (agreeing.length >= 2) {
      updates.push({ userId, delta: TRUST_CORROBORATION_REWARD });
    } else if (disagreeing.length >= 3) {
      updates.push({ userId, delta: -TRUST_OUTLIER_PENALTY });
    }
  }

  if (updates.length === 0) return;

  // Deduplicate: one update per user (take the first — reward or penalty, not both)
  const seen = new Set<string>();
  const deduped = updates.filter((u) => {
    if (seen.has(u.userId)) return false;
    seen.add(u.userId);
    return true;
  });

  const nowSeconds = Math.floor(now / 1000);

  for (const { userId, delta } of deduped) {
    // Idempotency: check if we already applied a trust update for this user+venue
    const markerSK = `${TRUST_UPDATE_SK_PREFIX}${venueId}`;
    const marker = await getItem(`USER#${userId}`, markerSK);
    if (marker) continue;

    await putItem({
      PK: `USER#${userId}`,
      SK: markerSK,
      ttl: nowSeconds + TRUST_MARKER_TTL_SECONDS,
    });

    // ADD is atomic — safe under concurrent updates from different venues
    await ddb.send(
      new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { userId },
        UpdateExpression: "SET trustScore = if_not_exists(trustScore, :default) + :delta",
        ExpressionAttributeValues: { ":default": DEFAULT_TRUST_SCORE, ":delta": delta },
      })
    ).catch(() => {});

    const profile = await ddb.send(
      new GetCommand({ TableName: USERS_TABLE, Key: { userId } })
    ).then((r) => r.Item);

    let score = profile?.trustScore as number | undefined;
    if (score != null && (score < TRUST_FLOOR || score > TRUST_CAP)) {
      score = Math.max(TRUST_FLOOR, Math.min(TRUST_CAP, score));
    }

    const reportLevel = (recentItems.find((i) => (i.userId as string) === userId)?.busynessLevel as number) ?? 0;
    const prevLevels = (profile?.recentLevels as number[] | undefined) ?? [];
    const updatedLevels = [...prevLevels, reportLevel].slice(-RECENT_LEVELS_SIZE);

    // Zero-variance penalty: if 10+ reports all the same level → likely bot
    let varianceDelta = 0;
    if (updatedLevels.length >= RECENT_LEVELS_SIZE) {
      const mean = updatedLevels.reduce((a, b) => a + b, 0) / updatedLevels.length;
      const variance = updatedLevels.reduce((a, b) => a + (b - mean) ** 2, 0) / updatedLevels.length;
      if (variance < 0.01) {
        varianceDelta = -VARIANCE_PENALTY;
      }
    }

    const finalScore = score != null
      ? Math.max(TRUST_FLOOR, score + varianceDelta)
      : undefined;

    const updateParts = ["recentLevels = :levels"];
    const exprValues: Record<string, unknown> = { ":levels": updatedLevels };
    if (finalScore != null && finalScore !== (profile?.trustScore as number | undefined)) {
      updateParts.push("trustScore = :score");
      exprValues[":score"] = finalScore;
    }
    await ddb.send(
      new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { userId },
        UpdateExpression: "SET " + updateParts.join(", "),
        ExpressionAttributeValues: exprValues,
      })
    ).catch(() => {});
  }

  log.debug("Trust scores updated", { venueId, count: deduped.length });
}
