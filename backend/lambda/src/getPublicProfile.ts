import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { GetCommand } from "@aws-sdk/lib-dynamodb";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { ddb } from "./db";
import { USERS_TABLE, PROFILE_IMAGES_BUCKET, success, badRequest, serverError } from "./shared";
import { createLogger } from "./logger";

const s3 = new S3Client({});

/**
 * GET /user/profile/{userId}/public
 * Returns non-sensitive profile data for display in leaderboard profiles.
 */
export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getPublicProfile", event, context);
  try {
    const targetUserId = event.pathParameters?.userId;
    if (!targetUserId) {
      return badRequest("Missing userId path parameter");
    }

    const result = await ddb.send(
      new GetCommand({
        TableName: USERS_TABLE,
        Key: { userId: targetUserId },
      })
    );

    if (!result.Item) {
      log.info("Public profile not found — returning placeholder", { targetUserId });
      return success({
        userId: targetUserId,
        displayName: "Anonymous",
        totalReports: 0,
        joinedAt: null,
        profileImageUrl: null,
        rankLevel: 1,
      });
    }

    const item = result.Item;
    const totalReports = (item.totalReports as number) ?? 0;

    let profileImageUrl: string | null = null;
    if (item.profileImageKey) {
      profileImageUrl = await getSignedUrl(
        s3,
        new GetObjectCommand({
          Bucket: PROFILE_IMAGES_BUCKET,
          Key: item.profileImageKey,
        }),
        { expiresIn: 3600 }
      );
    }

    // Mirrors iOS UserRank thresholds: newbie=1, explorer=5, scout=15, localGuide=30, legend=60
    let rankLevel = 1;
    if (totalReports >= 60) rankLevel = 5;
    else if (totalReports >= 30) rankLevel = 4;
    else if (totalReports >= 15) rankLevel = 3;
    else if (totalReports >= 5) rankLevel = 2;

    log.info("Public profile fetched", { targetUserId, totalReports, rankLevel });

    return success({
      userId: targetUserId,
      displayName: item.displayName ?? "Anonymous",
      totalReports,
      joinedAt: item.joinedAt ?? null,
      profileImageUrl,
      rankLevel,
    });
  } catch (err) {
    log.error("Failed to fetch public profile", undefined, err);
    return serverError("Failed to fetch public profile");
  }
}
