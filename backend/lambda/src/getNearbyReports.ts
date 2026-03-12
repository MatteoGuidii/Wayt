import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, ScanCommand } from "@aws-sdk/lib-dynamodb";
import {
  REPORTS_TABLE,
  VenueReportSummary,
  ReportItem,
  success,
  badRequest,
  serverError,
  haversineDistance,
} from "./shared";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

// Reports older than 2 hours are irrelevant
const MAX_AGE_MS = 2 * 60 * 60 * 1000;

export async function handler(
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> {
  try {
    const params = event.queryStringParameters ?? {};
    const lat = parseFloat(params.lat ?? "");
    const lng = parseFloat(params.lng ?? "");
    const radius = Math.min(parseInt(params.radius ?? "2000", 10), 10_000);

    if (isNaN(lat) || isNaN(lng)) {
      return badRequest("Missing or invalid lat/lng parameters");
    }

    // Bounding box for pre-filter (rough degrees → ~111km per degree)
    const degDelta = radius / 111_000;
    const now = Date.now();
    const cutoff = now - MAX_AGE_MS;

    // Scan with filter (fine for MVP; add GSI + geohash at scale)
    const result = await ddb.send(
      new ScanCommand({
        TableName: REPORTS_TABLE,
        FilterExpression:
          "lat BETWEEN :minLat AND :maxLat AND lng BETWEEN :minLng AND :maxLng AND #ts > :cutoff",
        ExpressionAttributeNames: { "#ts": "timestamp" },
        ExpressionAttributeValues: {
          ":minLat": lat - degDelta,
          ":maxLat": lat + degDelta,
          ":minLng": lng - degDelta,
          ":maxLng": lng + degDelta,
          ":cutoff": cutoff,
        },
      })
    );

    const items = (result.Items ?? []) as ReportItem[];

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

    return success({ venues });
  } catch (err) {
    console.error("[getNearbyReports] Error:", err);
    return serverError("Failed to fetch reports");
  }
}
