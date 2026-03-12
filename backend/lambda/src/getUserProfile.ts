import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand } from "@aws-sdk/lib-dynamodb";
import { USERS_TABLE, success, badRequest, serverError, getUserId } from "./shared";

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

    const result = await ddb.send(
      new GetCommand({
        TableName: USERS_TABLE,
        Key: { userId },
      })
    );

    if (result.Item) {
      return success({
        userId: result.Item.userId,
        username: result.Item.username,
        totalReports: result.Item.totalReports ?? 0,
        joinedAt: result.Item.joinedAt,
      });
    }

    // New user — return default profile
    return success({
      userId,
      username: userId.slice(0, 8),
      totalReports: 0,
      joinedAt: new Date().toISOString(),
    });
  } catch (err) {
    console.error("[getUserProfile] Error:", err);
    return serverError("Failed to fetch profile");
  }
}
