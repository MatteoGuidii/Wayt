import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { USERS_TABLE, success, badRequest, serverError, getUserId } from "./shared";
import { createLogger } from "./logger";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("updateUserProfile", event, context);
  try {
    const userId = getUserId(
      event.requestContext.authorizer?.claims as Record<string, string> | undefined
    );

    if (!userId) {
      return badRequest("Unauthorized");
    }

    let body: Record<string, unknown>;
    try {
      body = event.body ? JSON.parse(event.body) : {};
    } catch {
      return badRequest("Invalid JSON in request body");
    }
    const { displayName } = body;

    if (typeof displayName !== "string") {
      return badRequest("displayName is required");
    }

    const trimmed = displayName.trim();

    if (trimmed.length < 2 || trimmed.length > 30) {
      return badRequest("displayName must be 2-30 characters");
    }

    await ddb.send(
      new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { userId },
        UpdateExpression:
          "SET displayName = :name, updatedAt = :now, joinedAt = if_not_exists(joinedAt, :now)",
        ExpressionAttributeValues: {
          ":name": trimmed,
          ":now": new Date().toISOString(),
        },
      })
    );

    log.info("Profile updated");
    return success({ message: "Profile updated", displayName: trimmed });
  } catch (err) {
    log.error("Failed to update profile", undefined, err);
    return serverError("Failed to update profile");
  }
}
