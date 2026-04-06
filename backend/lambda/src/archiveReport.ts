import { DynamoDBStreamEvent } from "aws-lambda";
import { FirehoseClient, PutRecordCommand } from "@aws-sdk/client-firehose";
import { createHash } from "crypto";

const firehose = new FirehoseClient({});
const FIREHOSE_STREAM = process.env.FIREHOSE_STREAM_NAME!;
const ANALYTICS_SALT = process.env.ANALYTICS_SALT!;

function anonymize(userId: string): string {
  return createHash("sha256").update(`${userId}:${ANALYTICS_SALT}`).digest("hex").slice(0, 16);
}

export const handler = async (event: DynamoDBStreamEvent): Promise<void> => {
  const records = event.Records.filter((r) => r.eventName === "INSERT" && r.dynamodb?.NewImage);

  if (records.length === 0) return;

  const promises = records.map(async (record) => {
    const img = record.dynamodb!.NewImage!;

    const archived = {
      type: "report",
      anonId: anonymize(img.userId?.S ?? "unknown"),
      venueId: img.venueId?.S,
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

    await firehose.send(
      new PutRecordCommand({
        DeliveryStreamName: FIREHOSE_STREAM,
        Record: { Data: Buffer.from(JSON.stringify(archived) + "\n") },
      })
    );
  });

  await Promise.allSettled(promises);
};
