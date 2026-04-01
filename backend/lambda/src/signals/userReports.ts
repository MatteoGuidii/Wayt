import { QueryCommand } from "@aws-sdk/lib-dynamodb";
import { ddb, REPORTS_TABLE, venueKey, getItem, putItem } from "../db";
import { VenueSignal, SOURCE_CONFIG, normalizeLevel } from "./types";
import { createLogger } from "../logger";

/** How far back to look for reports (2 hours, matching the DynamoDB TTL). */
const MAX_AGE_MS = 2 * 60 * 60 * 1000;

/** Default cache TTL for aggregated report signal (5 minutes). */
const AGGREGATION_CACHE_TTL_SECONDS = 5 * 60;
/** Shorter cache TTL for high-activity venues (3+ reports) to support faster client refresh. */
const HIGH_ACTIVITY_CACHE_TTL_SECONDS = 2 * 60;
const REPORT_AGG_SK = "SIGNAL#user_reports_agg";

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

    // Compute weighted average with exponential decay
    let totalWeight = 0;
    let weightedBusyness = 0;
    let totalWaitWeight = 0;
    let weightedWait = 0;
    let waitCount = 0;
    let latestTimestamp = 0;

    for (const item of items) {
      const level = item.busynessLevel as number;
      const ts = item.timestamp as number;
      const ageMinutes = (now - ts) / 60_000;

      // Exponential decay: full weight at 0 min, ~37% at 60 min, ~14% at 120 min
      const weight = Math.exp(-ageMinutes / 60);

      weightedBusyness += level * weight;
      totalWeight += weight;
      latestTimestamp = Math.max(latestTimestamp, ts);

      if (item.waitMinutes != null) {
        weightedWait += (item.waitMinutes as number) * weight;
        totalWaitWeight += weight;
        waitCount++;
      }
    }

    if (totalWeight === 0) return null;

    const avgBusyness = weightedBusyness / totalWeight; // 1.0-5.0 scale
    const avgWait = totalWaitWeight > 0 ? Math.round(weightedWait / totalWaitWeight) : undefined;

    const config = SOURCE_CONFIG.user_reports;
    const reportCount = items.length;

    // Confidence: higher with more reports
    const confidence = reportCount >= 3 ? 0.9 : reportCount >= 2 ? 0.7 : 0.5;

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

    return signal;
  } catch (err) {
    const log = createLogger("userReports");
    log.error("Failed to aggregate reports", { venueId }, err);
    return null;
  }
}
