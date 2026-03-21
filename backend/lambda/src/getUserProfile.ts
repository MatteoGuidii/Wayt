import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand } from "@aws-sdk/lib-dynamodb";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import {
  USERS_TABLE,
  PROFILE_IMAGES_BUCKET,
  success,
  badRequest,
  serverError,
  getUserId,
} from "./shared";
import { createLogger } from "./logger";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const s3 = new S3Client({});

export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getUserProfile", event, context);
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
      let profileImageUrl: string | null = null;

      if (result.Item.profileImageKey) {
        profileImageUrl = await getSignedUrl(
          s3,
          new GetObjectCommand({
            Bucket: PROFILE_IMAGES_BUCKET,
            Key: result.Item.profileImageKey,
          }),
          { expiresIn: 3600 }
        );
      }

      return success({
        userId: result.Item.userId,
        username: result.Item.username,
        displayName: result.Item.displayName ?? null,
        totalReports: result.Item.totalReports ?? 0,
        joinedAt: result.Item.joinedAt,
        profileImageUrl,
      });
    }

    // New user — return default profile
    return success({
      userId,
      username: userId.slice(0, 8),
      displayName: null,
      totalReports: 0,
      joinedAt: new Date().toISOString(),
      profileImageUrl: null,
    });
  } catch (err) {
    log.error("Failed to fetch profile", undefined, err);
    return serverError("Failed to fetch profile");
  }
}
