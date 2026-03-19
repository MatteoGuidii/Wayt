import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand } from "@aws-sdk/lib-dynamodb";
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

    let venues: Record<string, unknown>[] = [];
    let lastKey: Record<string, unknown> | undefined;

    do {
      const result = await ddb.send(
        new QueryCommand({
          TableName: SAVED_VENUES_TABLE,
          KeyConditionExpression: "userId = :uid",
          ExpressionAttributeValues: { ":uid": userId },
          ...(lastKey && { ExclusiveStartKey: lastKey }),
        })
      );
      venues.push(...(result.Items ?? []));
      lastKey = result.LastEvaluatedKey;
    } while (lastKey);

    venues.sort(
      (a, b) => new Date(b.savedAt as string).getTime() - new Date(a.savedAt as string).getTime()
    );

    return success({ venues });
  } catch (err) {
    console.error("[listSavedVenues] Error:", err);
    return serverError("Failed to list saved venues");
  }
}
