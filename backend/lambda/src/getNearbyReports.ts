import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { QueryCommand } from "@aws-sdk/lib-dynamodb";
import { ddb, REPORTS_TABLE } from "./db";
import {
  VenueReportSummary,
  ReportItem,
  success,
  badRequest,
  serverError,
  haversineDistance,
} from "./shared";
import { neighborhood } from "./geohash";
import { createLogger } from "./logger";

// Reports older than 2 hours are irrelevant
const MAX_AGE_MS = 2 * 60 * 60 * 1000;

const GEOHASH_INDEX = "GeohashIndex";

/** Query a single geohash cell for reports newer than cutoff. */
async function queryCell(geohash: string, cutoff: number): Promise<ReportItem[]> {
  const result = await ddb.send(
    new QueryCommand({
      TableName: REPORTS_TABLE,
      IndexName: GEOHASH_INDEX,
      KeyConditionExpression: "geohash = :gh AND #ts > :cutoff",
      ExpressionAttributeNames: { "#ts": "timestamp" },
      ExpressionAttributeValues: {
        ":gh": geohash,
        ":cutoff": cutoff,
      },
      Limit: 1000,
      ScanIndexForward: false,
    })
  );
  return (result.Items ?? []) as ReportItem[];
}

export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getNearbyReports", event, context);
  const done = log.startTimer("Handler complete");
  try {
    const params = event.queryStringParameters ?? {};
    const lat = parseFloat(params.lat ?? "");
    const lng = parseFloat(params.lng ?? "");
    const radius = Math.min(parseInt(params.radius ?? "2000", 10), 10_000);

    if (isNaN(lat) || isNaN(lng)) {
      return badRequest("Missing or invalid lat/lng parameters");
    }

    log.info("Fetching nearby reports", { lat, lng, radius });
    const now = Date.now();
    const cutoff = now - MAX_AGE_MS;

    // Query the 9-cell geohash neighborhood (covers ~15km x 15km at precision 5)
    const cells = neighborhood(lat, lng);
    const cellResults = await Promise.all(cells.map((cell) => queryCell(cell, cutoff)));
    const items = cellResults.flat();

    // Filter by actual distance and aggregate by venue
    const venueMap = new Map<
      string,
      { totalBusyness: number; count: number; lastTimestamp: number; totalWait: number; waitCount: number }
    >();

    for (const item of items) {
      const dist = haversineDistance(lat, lng, item.lat, item.lng);
      if (dist > radius) continue;

      const existing = venueMap.get(item.venueId) ?? {
        totalBusyness: 0,
        count: 0,
        lastTimestamp: 0,
        totalWait: 0,
        waitCount: 0,
      };

      existing.totalBusyness += item.busynessLevel;
      existing.count += 1;
      existing.lastTimestamp = Math.max(existing.lastTimestamp, item.timestamp);

      if (item.waitMinutes != null) {
        existing.totalWait += item.waitMinutes;
        existing.waitCount += 1;
      }

      venueMap.set(item.venueId, existing);
    }

    // Build response
    const venues: VenueReportSummary[] = [];

    for (const [venueId, data] of venueMap) {
      const summary: VenueReportSummary = {
        venueId,
        avgBusyness: Math.round((data.totalBusyness / data.count) * 10) / 10,
        reportCount: data.count,
        lastReportedAt: new Date(data.lastTimestamp).toISOString(),
      };

      if (data.waitCount > 0) {
        summary.avgWaitMinutes = Math.round(data.totalWait / data.waitCount);
      }

      venues.push(summary);
    }

    done({ venueCount: venues.length, reportCount: items.length });
    return success({ venues });
  } catch (err) {
    log.error("Failed to fetch reports", undefined, err);
    return serverError("Failed to fetch reports");
  }
}
