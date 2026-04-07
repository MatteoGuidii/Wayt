import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { ddb } from "./db";
import {
  USERS_TABLE,
  PROFILE_IMAGES_BUCKET,
  success,
  badRequest,
  serverError,
  getUserId,
} from "./shared";
import { createLogger } from "./logger";
const s3 = new S3Client({});

export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getProfileUploadUrl", event, context);
  try {
    const userId = getUserId(
      event.requestContext.authorizer?.claims as Record<string, string> | undefined
    );

    if (!userId) {
      return badRequest("Unauthorized");
    }

    const imageKey = `profiles/${userId}/avatar.jpg`;

    // Generate presigned PUT URL (15 min expiry)
    const uploadUrl = await getSignedUrl(
      s3,
      new PutObjectCommand({
        Bucket: PROFILE_IMAGES_BUCKET,
        Key: imageKey,
        ContentType: "image/jpeg",
      }),
      { expiresIn: 900 }
    );

    // Store the image key in the user's profile
    await ddb.send(
      new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { userId },
        UpdateExpression:
          "SET profileImageKey = :key, joinedAt = if_not_exists(joinedAt, :now), updatedAt = :now",
        ExpressionAttributeValues: {
          ":key": imageKey,
          ":now": new Date().toISOString(),
        },
      })
    );

    log.info("Upload URL generated");
    return success({ uploadUrl, imageKey });
  } catch (err) {
    log.error("Failed to generate upload URL", undefined, err);
    return serverError("Failed to generate upload URL");
  }
}
