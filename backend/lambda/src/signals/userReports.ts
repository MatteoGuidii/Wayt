import { QueryCommand } from "@aws-sdk/lib-dynamodb";
import { ddb, REPORTS_TABLE } from "../db";
import { VenueSignal, SOURCE_CONFIG, normalizeLevel } from "./types";
import { createLogger } from "../logger";

/** How far back to look for reports (2 hours, matching the DynamoDB TTL). */
const MAX_AGE_MS = 2 * 60 * 60 * 1000;

/**
 * Aggregate user reports from the existing VenueReports table into a single
 * VenueSignal. Uses exponential decay weighting (mirrors the iOS BusynessEngine).
 *
 * Returns null if there are no recent reports for this venue.
 */
export async function aggregateUserReports(venueId: string): Promise<VenueSignal | null> {
  try {
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

    return {
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
  } catch (err) {
    const log = createLogger("userReports");
    log.error("Failed to aggregate reports", { venueId }, err);
    return null;
  }
}
