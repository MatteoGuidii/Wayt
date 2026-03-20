import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import {
  REPORTS_TABLE,
  USERS_TABLE,
  REPORT_TTL_SECONDS,
  SubmitReportBody,
  created,
  badRequest,
  serverError,
  getUserId,
} from "./shared";
import { venueKey, fusedSK, deleteItem } from "./db";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export async function handler(
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> {
  try {
    // Parse & validate
    const body: SubmitReportBody = JSON.parse(event.body ?? "{}");
    const { venueId, busynessLevel, waitMinutes, venueName, venueType, lat, lng } = body;

    if (!venueId || !venueName || !venueType || lat == null || lng == null) {
      return badRequest("Missing required fields: venueId, venueName, venueType, lat, lng");
    }

    if (!Number.isInteger(busynessLevel) || busynessLevel < 1 || busynessLevel > 5) {
      return badRequest("busynessLevel must be an integer 1-5");
    }

    // Auth
    const userId = getUserId(
      event.requestContext.authorizer?.claims as Record<string, string> | undefined
    );
    if (!userId) {
      return badRequest("Unauthorized");
    }

    const now = Date.now();
    const reportId = `${venueId}_${now}_${userId.slice(0, 8)}`;
    const ttl = Math.floor(now / 1000) + REPORT_TTL_SECONDS;

    // Write report
    await ddb.send(
      new PutCommand({
        TableName: REPORTS_TABLE,
        Item: {
          venueId,
          timestamp: now,
          reportId,
          userId,
          busynessLevel,
          ...(waitMinutes != null && { waitMinutes }),
          venueName,
          venueType,
          lat,
          lng,
          ttl,
        },
      })
    );

    // Increment user's report count (atomic)
    await ddb.send(
      new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { userId },
        UpdateExpression:
          "SET totalReports = if_not_exists(totalReports, :zero) + :one, username = if_not_exists(username, :name), joinedAt = if_not_exists(joinedAt, :now)",
        ExpressionAttributeValues: {
          ":zero": 0,
          ":one": 1,
          ":name": userId.slice(0, 8),
          ":now": new Date().toISOString(),
        },
      })
    );

    // Invalidate cached fused estimate so next query recomputes with fresh data
    try {
      await deleteItem(venueKey(venueId), fusedSK());
    } catch {
      // Non-critical — cache will expire naturally via TTL
    }

    return created({ reportId, message: "Report submitted" });
  } catch (err) {
    console.error("[submitReport] Error:", err);
    return serverError("Failed to submit report");
  }
}
