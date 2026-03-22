import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import {
  SAVED_VENUES_TABLE,
  SaveVenueBody,
  created,
  badRequest,
  serverError,
  getUserId,
} from "./shared";
import { createLogger } from "./logger";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("saveVenue", event, context);
  const userId = getUserId(
    event.requestContext.authorizer?.claims as Record<string, string> | undefined
  );
  if (!userId) {
    return badRequest("Unauthorized");
  }

  let body: SaveVenueBody;
  try {
    body = JSON.parse(event.body ?? "{}");
  } catch {
    return badRequest("Invalid JSON in request body");
  }

  try {
    const { venueId, venueName, categoryRaw, lat, lng, address } = body;

    if (!venueId || !venueName || !categoryRaw || lat == null || lng == null) {
      return badRequest("Missing required fields: venueId, venueName, categoryRaw, lat, lng");
    }

    log.info("Saving venue", { venueId });
    const now = new Date().toISOString();

    await ddb.send(
      new PutCommand({
        TableName: SAVED_VENUES_TABLE,
        Item: {
          userId,
          venueId,
          venueName,
          categoryRaw,
          lat,
          lng,
          ...(address != null && { address }),
          savedAt: now,
        },
      })
    );

    log.info("Venue saved", { venueId });
    return created({ venueId, message: "Venue saved" });
  } catch (err) {
    log.error("Failed to save venue", undefined, err);
    return serverError("Failed to save venue");
  }
}
