import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
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

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export async function handler(
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> {
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

    return created({ venueId, message: "Venue saved" });
  } catch (err) {
    console.error("[saveVenue] Error:", err);
    return serverError("Failed to save venue");
  }
}
