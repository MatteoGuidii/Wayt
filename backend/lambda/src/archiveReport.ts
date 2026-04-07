import { DynamoDBStreamEvent, Context } from "aws-lambda";
import { FirehoseClient, PutRecordCommand } from "@aws-sdk/client-firehose";
import { createHash } from "crypto";
import { createLogger } from "./logger";

const firehose = new FirehoseClient({});
const FIREHOSE_STREAM = process.env.FIREHOSE_STREAM_NAME!;
const ANALYTICS_SALT = process.env.ANALYTICS_SALT!;

function anonymize(userId: string): string {
  return createHash("sha256").update(`${userId}:${ANALYTICS_SALT}`).digest("hex").slice(0, 16);
}

export const handler = async (
  event: DynamoDBStreamEvent,
  context: Context
): Promise<void> => {
  // Stream-triggered Lambda — no API Gateway event, so no userId/claims to leak.
  const log = createLogger("archiveReport", undefined, context);

  const totalRecords = event.Records.length;
  const records = event.Records.filter((r) => r.eventName === "INSERT" && r.dynamodb?.NewImage);

  if (records.length === 0) {
    log.info("No INSERT records to archive", { totalRecords });
    return;
  }

  log.info("Archiving reports", { totalRecords, insertCount: records.length });

  const promises = records.map(async (record) => {
    const img = record.dynamodb!.NewImage!;
    const venueId = img.venueId?.S;

    const archived = {
      type: "report",
      anonId: anonymize(img.userId?.S ?? "unknown"),
      venueId,
      busynessLevel: Number(img.busynessLevel?.N ?? 0),
      waitMinutes: img.waitMinutes?.N ? Number(img.waitMinutes.N) : null,
      venueName: img.venueName?.S,
      venueType: img.venueType?.S,
      lat: Number(img.lat?.N ?? 0),
      lng: Number(img.lng?.N ?? 0),
      geohash: img.geohash?.S,
      timestamp: Number(img.timestamp?.N ?? 0),
      archivedAt: new Date().toISOString(),
    };

    try {
      await firehose.send(
        new PutRecordCommand({
          DeliveryStreamName: FIREHOSE_STREAM,
          Record: { Data: Buffer.from(JSON.stringify(archived) + "\n") },
        })
      );
      return { ok: true as const, venueId };
    } catch (err) {
      return { ok: false as const, venueId, error: String(err) };
    }
  });

  const results = await Promise.all(promises);
  const archived = results.filter((r) => r.ok).length;
  const failed = results.filter((r) => !r.ok);

  if (failed.length > 0) {
    log.error("Some archives failed", {
      archived,
      failed: failed.length,
      failedVenues: failed.slice(0, 5).map((f) => ({ venueId: f.venueId, error: f.error })),
    });
  } else {
    log.info("Archive batch complete", { archived });
  }
};
