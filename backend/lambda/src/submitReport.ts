import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { PutCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { ddb, REPORTS_TABLE, venueKey, fusedSK, deleteItem } from "./db";
import {
  USERS_TABLE,
  REPORT_TTL_SECONDS,
  SubmitReportBody,
  created,
  badRequest,
  serverError,
  getUserId,
} from "./shared";
import { encode } from "./geohash";
import { createLogger } from "./logger";

export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("submitReport", event, context);
  const done = log.startTimer("Handler complete");
  try {
    // Parse & validate
    const body: SubmitReportBody = JSON.parse(event.body ?? "{}");
    const { venueId, busynessLevel, waitMinutes, venueName, venueType, lat, lng } = body;

    if (!venueId || !venueName || !venueType || lat == null || lng == null) {
      log.warn("Validation failed", { reason: "missing fields" });
      return badRequest("Missing required fields: venueId, venueName, venueType, lat, lng");
    }

    if (!Number.isInteger(busynessLevel) || busynessLevel < 1 || busynessLevel > 5) {
      log.warn("Validation failed", { reason: "invalid busynessLevel", busynessLevel });
      return badRequest("busynessLevel must be an integer 1-5");
    }

    if (waitMinutes != null && (typeof waitMinutes !== "number" || waitMinutes < 0 || waitMinutes > 300)) {
      log.warn("Validation failed", { reason: "invalid waitMinutes", waitMinutes });
      return badRequest("waitMinutes must be a number between 0 and 300");
    }

    log.info("Submitting report", { venueId, busynessLevel });

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

    // Write report (geohash enables efficient spatial queries via GSI)
    const geohash = encode(lat, lng);
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
          geohash,
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

    log.info("Report written", { reportId, venueId });

    // Invalidate cached fused estimate so next query recomputes with fresh data.
    // user_reports signals are never cached in SIGNALS_TABLE (always re-aggregated
    // from REPORTS_TABLE), so deleting FUSED#CURRENT is sufficient.
    try {
      await deleteItem(venueKey(venueId), fusedSK());
    } catch {
      log.warn("Fused cache invalidation failed (non-critical)");
    }

    done({ reportId, venueId });
    return created({ reportId, message: "Report submitted" });
  } catch (err) {
    log.error("Report submission failed", undefined, err);
    return serverError("Failed to submit report");
  }
}
