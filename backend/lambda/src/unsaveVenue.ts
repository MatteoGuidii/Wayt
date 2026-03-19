import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import {
  SAVED_VENUES_TABLE,
  success,
  badRequest,
  serverError,
  getUserId,
} from "./shared";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export async function handler(
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> {
  try {
    const userId = getUserId(
      event.requestContext.authorizer?.claims as Record<string, string> | undefined
    );
    if (!userId) {
      return badRequest("Unauthorized");
    }

    const body = JSON.parse(event.body ?? "{}");
    const { venueId } = body as { venueId?: string };

    if (!venueId) {
      return badRequest("Missing required field: venueId");
    }

    await ddb.send(
      new DeleteCommand({
        TableName: SAVED_VENUES_TABLE,
        Key: { userId, venueId },
      })
    );

    return success({ venueId, message: "Venue unsaved" });
  } catch (err) {
    console.error("[unsaveVenue] Error:", err);
    return serverError("Failed to unsave venue");
  }
}
