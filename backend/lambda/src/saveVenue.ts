import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { PutCommand } from "@aws-sdk/lib-dynamodb";
import { ddb } from "./db";
import {
  SAVED_VENUES_TABLE,
  SaveVenueBody,
  created,
  badRequest,
  serverError,
  getUserId,
} from "./shared";
import { createLogger } from "./logger";

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

    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return badRequest("Invalid coordinates: lat must be -90..90, lng must be -180..180");
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
