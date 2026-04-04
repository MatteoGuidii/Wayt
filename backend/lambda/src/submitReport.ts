import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { DeleteCommand, GetCommand, PutCommand, QueryCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { ddb, REPORTS_TABLE, venueKey, fusedSK, getItem, deleteItem } from "./db";
import {
  USERS_TABLE,
  REPORT_TTL_SECONDS,
  REPORT_COOLDOWN_SECONDS,
  REPORT_MAX_DISTANCE_M,
  DAILY_REPORT_CAP,
  DEFAULT_TRUST_SCORE,
  NEW_ACCOUNT_TRUST_SCORE,
  NEW_ACCOUNT_THRESHOLD_MS,
  VELOCITY_MAX_REPORTS,
  VELOCITY_WINDOW_MS,
  SubmitReportBody,
  created,
  badRequest,
  tooManyRequests,
  serverError,
  getUserId,
  haversineDistance,
  getISOWeekKey,
} from "./shared";
import { isOpenNow, CachedGoogleHours, GoogleOpenPeriod } from "./signals/google";
import { encode } from "./geohash";
import { createLogger } from "./logger";

const LEADERBOARD_TABLE = process.env.LEADERBOARD_TABLE ?? "";

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

    // Daily report cap — use client timezone so the date matches the user's local day
    const clientTz = body.timezone || "UTC";
    let today: string;
    try {
      today = new Date(now).toLocaleDateString("en-CA", { timeZone: clientTz });
    } catch {
      // Invalid timezone identifier — fall back to UTC
      today = new Date(now).toISOString().slice(0, 10);
    }
    const dailyDate = (userProfile?.dailyReportDate as string | undefined) ?? "";
    const dailyCount = dailyDate === today ? (userProfile?.dailyReportCount as number ?? 0) : 0;
    if (dailyCount >= DAILY_REPORT_CAP) {
      log.info("Report rejected: daily cap reached", { userId, dailyCount });
      return tooManyRequests({
        error: "DAILY_LIMIT_REACHED",
        message: "You've reached the daily report limit. Try again tomorrow.",
      });
    }

    // Velocity check — prevent rapid-fire reports across different venues
    const recentTimestamps = (userProfile?.recentReportTimestamps as number[] | undefined) ?? [];
    const recentWithinWindow = recentTimestamps.filter((ts) => (now - ts) < VELOCITY_WINDOW_MS);
    if (recentWithinWindow.length >= VELOCITY_MAX_REPORTS) {
      log.info("Report rejected: velocity limit", { userId, reportsInWindow: recentWithinWindow.length });
      return tooManyRequests({
        error: "VELOCITY_LIMIT",
        message: "You're reporting too quickly. Please slow down.",
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
        if (openStatus.isOpen === false) {
          log.info("Report rejected: venue currently closed", { venueId });
          return badRequest("This venue appears to be closed right now");
        }
      }
    }

    const reportId = `${venueId}_${now}_${crypto.randomUUID().slice(0, 8)}`;
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

    // Increment user's report count + daily counter + initialize trust score
    const joinedAt = userProfile?.joinedAt as string | undefined;
    const isNewAccount = !joinedAt || (now - new Date(joinedAt).getTime()) < NEW_ACCOUNT_THRESHOLD_MS;
    const initialTrust = isNewAccount ? NEW_ACCOUNT_TRUST_SCORE : DEFAULT_TRUST_SCORE;

    const updatedTimestamps = [...recentWithinWindow, now].slice(-VELOCITY_MAX_REPORTS);

    const existingReportDates = (userProfile?.reportDates as string[] | undefined) ?? [];
    const cutoffDate = new Date(now - 90 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const updatedReportDates = [...new Set([...existingReportDates, today])]
      .filter((d) => d >= cutoffDate)
      .sort();

    await ddb.send(
      new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { userId },
        UpdateExpression:
          "SET totalReports = if_not_exists(totalReports, :zero) + :one, " +
          "username = if_not_exists(username, :name), " +
          "joinedAt = if_not_exists(joinedAt, :now), " +
          "trustScore = if_not_exists(trustScore, :initTrust), " +
          "dailyReportCount = :newDailyCount, " +
          "dailyReportDate = :today, " +
          "recentReportTimestamps = :timestamps, " +
          "reportDates = :reportDates, " +
          "lastReportDate = :lastReportDate, " +
          "confirmationsReceived = if_not_exists(confirmationsReceived, :zero)",
        ExpressionAttributeValues: {
          ":zero": 0,
          ":one": 1,
          ":name": userId.slice(0, 8),
          ":now": new Date().toISOString(),
          ":initTrust": initialTrust,
          ":newDailyCount": dailyCount + 1,
          ":today": today,
          ":timestamps": updatedTimestamps,
          ":reportDates": updatedReportDates,
          ":lastReportDate": today,
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

    // Engagement side-effects (non-critical, fire after cache invalidation)
    const sideEffects: Promise<void>[] = [
      updateConfirmations(venueId, userId, busynessLevel, now, log),
    ];
    if (LEADERBOARD_TABLE) {
      sideEffects.push(updateLeaderboard(userId, lat, lng, now, log));
    }
    const settled = await Promise.allSettled(sideEffects);
    for (const r of settled) {
      if (r.status === "rejected") log.warn("Side-effect failed", { error: String(r.reason) });
    }

    done({ reportId, venueId });
    return created({ reportId, message: "Report submitted" });
  } catch (err) {
    log.error("Report submission failed", undefined, err);
    return serverError("Failed to submit report");
  }
}

// -----------------------------------------------
// Report Confirmation Helper
// -----------------------------------------------

/**
 * When a user submits a report, check if other users recently reported the same
 * venue with a similar busyness level (±1). If so, increment their
 * confirmationsReceived counter — this closes the social validation loop.
 */
async function updateConfirmations(
  venueId: string,
  reporterId: string,
  busynessLevel: number,
  now: number,
  log: ReturnType<typeof createLogger>
): Promise<void> {
  const cutoff = now - REPORT_TTL_SECONDS * 1000;
  const result = await ddb.send(
    new QueryCommand({
      TableName: REPORTS_TABLE,
      KeyConditionExpression: "venueId = :vid AND #ts > :cutoff",
      FilterExpression: "userId <> :uid",
      ExpressionAttributeNames: { "#ts": "timestamp" },
      ExpressionAttributeValues: {
        ":vid": venueId,
        ":cutoff": cutoff,
        ":uid": reporterId,
      },
    })
  );

  const confirmedUserIds = new Set<string>();
  for (const report of result.Items ?? []) {
    const reportLevel = report.busynessLevel as number;
    if (Math.abs(reportLevel - busynessLevel) <= 1) {
      confirmedUserIds.add(report.userId as string);
    }
  }

  if (confirmedUserIds.size === 0) return;

  log.info("Confirming reports", { venueId, confirmedUsers: confirmedUserIds.size });

  await Promise.all(
    [...confirmedUserIds].map((uid) =>
      ddb.send(
        new UpdateCommand({
          TableName: USERS_TABLE,
          Key: { userId: uid },
          UpdateExpression:
            "SET confirmationsReceived = if_not_exists(confirmationsReceived, :zero) + :one",
          ExpressionAttributeValues: { ":zero": 0, ":one": 1 },
        })
      )
    )
  );
}

// -----------------------------------------------
// Weekly Leaderboard Helper
// -----------------------------------------------

/**
 * Upsert the user's weekly leaderboard entry.
 * Since score is the RANGE key, we delete the old entry and write a new one
 * with the incremented score so top-N queries stay correct.
 *
 * Note: read-delete-write is not atomic — concurrent reports by the same user
 * can lose a count. Acceptable for a weekly leaderboard with 8-day TTL.
 */
async function updateLeaderboard(
  userId: string,
  lat: number,
  lng: number,
  now: number,
  log: ReturnType<typeof createLogger>
): Promise<void> {
  const weekKey = getISOWeekKey(new Date(now));
  const geohash4 = encode(lat, lng, 4);
  const partitionKey = `${weekKey}#${geohash4}`;
  const ttl = Math.floor(now / 1000) + 8 * 24 * 60 * 60; // 8 days

  const existing = await ddb.send(
    new QueryCommand({
      TableName: LEADERBOARD_TABLE,
      KeyConditionExpression: "weekGeohash = :wg",
      FilterExpression: "userId = :uid",
      ExpressionAttributeValues: { ":wg": partitionKey, ":uid": userId },
    })
  );

  const oldEntry = existing.Items?.[0];
  const oldScore = (oldEntry?.score as number) ?? 0;
  const oldReportCount = (oldEntry?.reportCount as number) ?? 0;
  const newReportCount = oldReportCount + 1;
  const newScore = newReportCount * 10_000_000_000_000 + now;

  if (oldEntry) {
    await ddb.send(
      new DeleteCommand({
        TableName: LEADERBOARD_TABLE,
        Key: { weekGeohash: partitionKey, score: oldScore },
      })
    );
  }

  await ddb.send(
    new PutCommand({
      TableName: LEADERBOARD_TABLE,
      Item: {
        weekGeohash: partitionKey,
        score: newScore,
        userId,
        reportCount: newReportCount,
        ttl,
      },
    })
  );

  log.info("Leaderboard updated", { weekKey, geohash4, userId, reportCount: newReportCount });
}
