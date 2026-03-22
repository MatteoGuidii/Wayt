import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import {
  SAVED_VENUES_TABLE,
  success,
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
  const log = createLogger("unsaveVenue", event, context);
  const userId = getUserId(
    event.requestContext.authorizer?.claims as Record<string, string> | undefined
  );
  if (!userId) {
    return badRequest("Unauthorized");
  }

  let body: { venueId?: string };
  try {
    body = JSON.parse(event.body ?? "{}");
  } catch {
    return badRequest("Invalid JSON in request body");
  }

  const { venueId } = body;

  try {

    if (!venueId) {
      return badRequest("Missing required field: venueId");
    }

    log.info("Unsaving venue", { venueId });
    await ddb.send(
      new DeleteCommand({
        TableName: SAVED_VENUES_TABLE,
        Key: { userId, venueId },
      })
    );

    return success({ venueId, message: "Venue unsaved" });
  } catch (err) {
    log.error("Failed to unsave venue", undefined, err);
    return serverError("Failed to unsave venue");
  }
}
