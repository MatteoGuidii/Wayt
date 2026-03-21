import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand } from "@aws-sdk/lib-dynamodb";
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
  const log = createLogger("listSavedVenues", event, context);
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

    log.info("Listed saved venues", { count: venues.length });
    return success({ venues });
  } catch (err) {
    log.error("Failed to list saved venues", undefined, err);
    return serverError("Failed to list saved venues");
  }
}
