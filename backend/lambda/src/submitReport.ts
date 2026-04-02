import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { GetCommand, PutCommand, QueryCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { ddb, REPORTS_TABLE, venueKey, fusedSK, getItem, deleteItem } from "./db";
import {
  USERS_TABLE,
  REPORT_TTL_SECONDS,
  REPORT_COOLDOWN_SECONDS,
  REPORT_MAX_DISTANCE_M,
  DAILY_REPORT_CAP,
  SubmitReportBody,
  created,
  badRequest,
  tooManyRequests,
  serverError,
  getUserId,
  haversineDistance,
} from "./shared";
import { isOpenNow, CachedGoogleHours, GoogleOpenPeriod } from "./signals/google";
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

    // Cooldown check: reject if the same user reported this venue within 30 minutes
    const cooldownCutoff = now - REPORT_COOLDOWN_SECONDS * 1000;
    const recentByUser = await ddb.send(
      new QueryCommand({
        TableName: REPORTS_TABLE,
        KeyConditionExpression: "venueId = :vid AND #ts > :cutoff",
        FilterExpression: "userId = :uid",
        ExpressionAttributeNames: { "#ts": "timestamp" },
        ExpressionAttributeValues: {
          ":vid": venueId,
          ":cutoff": cooldownCutoff,
          ":uid": userId,
        },
        ScanIndexForward: false,
      })
    );

    if (recentByUser.Items && recentByUser.Items.length > 0) {
      const lastTimestamp = recentByUser.Items[0].timestamp as number;
      const retryAfter = Math.ceil(
        REPORT_COOLDOWN_SECONDS - (now - lastTimestamp) / 1000
      );
      log.info("Cooldown active", { venueId, userId, retryAfter });
      return tooManyRequests({
        error: "COOLDOWN_ACTIVE",
        message: "You reported this venue recently. Please wait before reporting again.",
        retryAfter,
      });
    }

    // Validation gates (parallel fetch to minimize latency)
    const [fusedEntry, gdataEntry, userProfileResult] = await Promise.all([
      getItem(venueKey(venueId), fusedSK()),
      getItem(venueKey(venueId), "GDATA#CURRENT"),
      ddb.send(new GetCommand({ TableName: USERS_TABLE, Key: { userId } })),
    ]);
    const userProfile = userProfileResult.Item;

    // GPS proximity check
    if (fusedEntry) {
      const venueLat = fusedEntry.lat as number;
      const venueLng = fusedEntry.lng as number;
      if (venueLat != null && venueLng != null) {
        const distance = haversineDistance(lat, lng, venueLat, venueLng);
        if (distance > REPORT_MAX_DISTANCE_M) {
          log.info("Report rejected: too far from venue", { venueId, distance: Math.round(distance) });
          return badRequest("You appear too far from this venue to report");
        }
      }
    }

    // Daily report cap
    const today = new Date(now).toISOString().slice(0, 10);
    const dailyDate = (userProfile?.dailyReportDate as string | undefined) ?? "";
    const dailyCount = dailyDate === today ? (userProfile?.dailyReportCount as number ?? 0) : 0;
    if (dailyCount >= DAILY_REPORT_CAP) {
      log.info("Report rejected: daily cap reached", { userId, dailyCount });
      return tooManyRequests({
        error: "DAILY_LIMIT_REACHED",
        message: "You've reached the daily report limit. Try again tomorrow.",
      });
    }

    // Closed-venue guard
    if (gdataEntry) {
      const businessStatus = gdataEntry.businessStatus as string | null;
      if (businessStatus === "CLOSED_PERMANENTLY" || businessStatus === "CLOSED_TEMPORARILY") {
        log.info("Report rejected: venue closed", { venueId, businessStatus });
        return badRequest("This venue appears to be closed");
      }
      const cachedHours: CachedGoogleHours = {
        businessStatus: (businessStatus as CachedGoogleHours["businessStatus"]) ?? null,
        regularPeriods: (gdataEntry.regularPeriods as GoogleOpenPeriod[]) ?? [],
        cachedAt: gdataEntry.cachedAt as string,
      };
      if (body.timezone && cachedHours.regularPeriods.length > 0) {
        const openStatus = isOpenNow(cachedHours, now, body.timezone);
        if (!openStatus.isOpen) {
          log.info("Report rejected: venue currently closed", { venueId });
          return badRequest("This venue appears to be closed right now");
        }
      }
    }

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

    // Increment user's report count + daily counter (atomic)
    await ddb.send(
      new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { userId },
        UpdateExpression:
          "SET totalReports = if_not_exists(totalReports, :zero) + :one, " +
          "username = if_not_exists(username, :name), " +
          "joinedAt = if_not_exists(joinedAt, :now), " +
          "dailyReportCount = :newDailyCount, " +
          "dailyReportDate = :today",
        ExpressionAttributeValues: {
          ":zero": 0,
          ":one": 1,
          ":name": userId.slice(0, 8),
          ":now": new Date().toISOString(),
          ":newDailyCount": dailyCount + 1,
          ":today": today,
        },
      })
    );

    log.info("Report written", { reportId, venueId });

    // Invalidate cached fused estimate and aggregated report signal so next query
    // recomputes with the fresh report included.
    try {
      await Promise.all([
        deleteItem(venueKey(venueId), fusedSK()),
        deleteItem(venueKey(venueId), "SIGNAL#user_reports_agg"),
      ]);
    } catch {
      log.warn("Cache invalidation failed (non-critical)");
    }

    done({ reportId, venueId });
    return created({ reportId, message: "Report submitted" });
  } catch (err) {
    log.error("Report submission failed", undefined, err);
    return serverError("Failed to submit report");
  }
}
