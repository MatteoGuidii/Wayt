import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import { FirehoseClient, PutRecordBatchCommand } from "@aws-sdk/client-firehose";
import { UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { createHash } from "crypto";
import { createLogger } from "./logger";
import { ddb, SIGNALS_TABLE, venueKey } from "./db";
import {
  accepted,
  badRequest,
  serverError,
  getUserId,
  ANALYTICS_MAX_BATCH_SIZE,
  AnalyticsEvent,
} from "./shared";

const firehose = new FirehoseClient({});
const FIREHOSE_STREAM = process.env.FIREHOSE_STREAM_NAME!;
const ANALYTICS_SALT = process.env.ANALYTICS_SALT!;

function anonymize(userId: string): string {
  return createHash("sha256").update(`${userId}:${ANALYTICS_SALT}`).digest("hex").slice(0, 16);
}

function todayKey(): string {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  const log = createLogger("ingestEvents", event);

  const userId = getUserId(event.requestContext.authorizer?.claims);
  if (!userId) return badRequest("Unauthorized");

  let body: { events?: AnalyticsEvent[] };
  try {
    body = JSON.parse(event.body ?? "{}");
  } catch {
    return badRequest("Invalid JSON");
  }

  const events = body.events;
  if (!Array.isArray(events) || events.length === 0) {
    return badRequest("events array required");
  }
  if (events.length > ANALYTICS_MAX_BATCH_SIZE) {
    return badRequest(`Max ${ANALYTICS_MAX_BATCH_SIZE} events per batch`);
  }

  const anonId = anonymize(userId);
  const day = todayKey();
  const now = Date.now();

  // Write all events to Firehose
  const firehoseRecords = events.map((e) => ({
    Data: Buffer.from(
      JSON.stringify({
        type: "event",
        anonId,
        eventType: e.eventType,
        timestamp: e.timestamp,
        sessionId: e.sessionId,
        lat: e.lat,
        lng: e.lng,
        venueId: e.venueId,
        venueName: e.venueName,
        venueType: e.venueType,
        properties: e.properties,
        ingestedAt: new Date(now).toISOString(),
      }) + "\n"
    ),
  }));

  // Increment venue view counters for venue_view events
  const venueViews = new Map<string, number>();
  for (const e of events) {
    if (e.eventType === "venue_view" && e.venueId) {
      venueViews.set(e.venueId, (venueViews.get(e.venueId) ?? 0) + 1);
    }
  }

  try {
    // Fire-and-forget Firehose write (batched, max 500 per call, we cap at 50)
    const firehosePromise = firehose.send(
      new PutRecordBatchCommand({
        DeliveryStreamName: FIREHOSE_STREAM,
        Records: firehoseRecords,
      })
    );

    // Increment daily view counters
    const counterPromises = Array.from(venueViews.entries()).map(
      ([venueId, count]) =>
        ddb.send(
          new UpdateCommand({
            TableName: SIGNALS_TABLE,
            Key: { PK: venueKey(venueId), SK: `VIEWS#${day}` },
            UpdateExpression: "ADD viewCount :c SET #ttl = if_not_exists(#ttl, :ttl)",
            ExpressionAttributeNames: { "#ttl": "ttl" },
            ExpressionAttributeValues: {
              ":c": count,
              ":ttl": Math.floor(now / 1000) + 90 * 24 * 60 * 60, // 90 days
            },
          })
        )
    );

    await Promise.allSettled([firehosePromise, ...counterPromises]);

    log.info("Events ingested", { count: events.length, viewCounters: venueViews.size });
  } catch (err) {
    log.error("Ingestion failed", undefined, err);
    return serverError("Ingestion failed");
  }

  return accepted({ ingested: events.length });
};
