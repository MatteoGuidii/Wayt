import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { QueryCommand, GetCommand } from "@aws-sdk/lib-dynamodb";
import { ddb } from "./db";
import { USERS_TABLE, success, badRequest, serverError, getUserId, getISOWeekKey } from "./shared";
import { encode } from "./geohash";
import { createLogger } from "./logger";

const LEADERBOARD_TABLE = process.env.LEADERBOARD_TABLE!;

/**
 * GET /leaderboard/nearby?lat=X&lng=Y
 * Returns the top 10 reporters in the user's geohash area for the current week.
 */
export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getLeaderboard", event, context);
  try {
    const lat = parseFloat(event.queryStringParameters?.lat ?? "");
    const lng = parseFloat(event.queryStringParameters?.lng ?? "");

    if (isNaN(lat) || isNaN(lng)) {
      return badRequest("Missing required query parameters: lat, lng");
    }

    const userId = getUserId(
      event.requestContext.authorizer?.claims as Record<string, string> | undefined
    );
    if (!userId) {
      return badRequest("Unauthorized");
    }

    const weekKey = getISOWeekKey(new Date());
    const geohash4 = encode(lat, lng, 4);
    const partitionKey = `${weekKey}#${geohash4}`;

    const result = await ddb.send(
      new QueryCommand({
        TableName: LEADERBOARD_TABLE,
        KeyConditionExpression: "weekGeohash = :wg",
        ExpressionAttributeValues: { ":wg": partitionKey },
        ScanIndexForward: false,
        Limit: 10,
      })
    );

    const entries = result.Items ?? [];

    const userIds = entries.map((e) => e.userId as string);
    const profiles = await resolveDisplayNames(userIds);

    const leaderboard = entries.map((entry, index) => {
      const uid = entry.userId as string;
      const profile = profiles.get(uid);
      return {
        rank: index + 1,
        userId: uid,
        displayName: profile?.displayName ?? profile?.username ?? "Anonymous",
        reportCount: entry.reportCount as number,
        isCurrentUser: uid === userId,
      };
    });

    // Find current user's position if not in top 10
    let currentUserEntry: { rank: number; reportCount: number } | null = null;
    if (!leaderboard.some((e) => e.isCurrentUser)) {
      const userResult = await ddb.send(
        new QueryCommand({
          TableName: LEADERBOARD_TABLE,
          KeyConditionExpression: "weekGeohash = :wg",
          FilterExpression: "userId = :uid",
          ExpressionAttributeValues: { ":wg": partitionKey, ":uid": userId },
        })
      );
      if (userResult.Items && userResult.Items.length > 0) {
        const userItem = userResult.Items[0];
        const allResult = await ddb.send(
          new QueryCommand({
            TableName: LEADERBOARD_TABLE,
            KeyConditionExpression: "weekGeohash = :wg AND score > :s",
            ExpressionAttributeValues: {
              ":wg": partitionKey,
              ":s": userItem.score as number,
            },
            Select: "COUNT",
          })
        );
        currentUserEntry = {
          rank: (allResult.Count ?? 0) + 1,
          reportCount: userItem.reportCount as number,
        };
      }
    }

    log.info("Leaderboard fetched", { geohash4, entries: leaderboard.length });

    return success({
      weekKey,
      leaderboard,
      currentUserEntry,
    });
  } catch (err) {
    log.error("Leaderboard fetch failed", undefined, err);
    return serverError("Failed to fetch leaderboard");
  }
}

async function resolveDisplayNames(
  userIds: string[]
): Promise<Map<string, { displayName?: string; username?: string }>> {
  const result = new Map<string, { displayName?: string; username?: string }>();
  if (userIds.length === 0) return result;

  await Promise.all(
    userIds.map(async (uid) => {
      try {
        const res = await ddb.send(
          new GetCommand({ TableName: USERS_TABLE, Key: { userId: uid } })
        );
        if (res.Item) {
          result.set(uid, {
            displayName: res.Item.displayName as string | undefined,
            username: res.Item.username as string | undefined,
          });
        }
      } catch {
        // Non-critical — display as Anonymous
      }
    })
  );

  return result;
}
