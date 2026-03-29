import {
  APIGatewayProxyEvent,
  APIGatewayProxyResult,
  Context,
} from "aws-lambda";
import {
  DeleteCommand,
  QueryCommand,
  ScanCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import { DeleteObjectCommand, S3Client } from "@aws-sdk/client-s3";
import {
  CognitoIdentityProviderClient,
  AdminDeleteUserCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { ddb, REPORTS_TABLE } from "./db";
import {
  USERS_TABLE,
  SAVED_VENUES_TABLE,
  PROFILE_IMAGES_BUCKET,
  USER_POOL_ID,
  success,
  badRequest,
  serverError,
  getUserId,
} from "./shared";
import { createLogger } from "./logger";

const s3 = new S3Client({});
const cognito = new CognitoIdentityProviderClient({});

export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("deleteAccount", event, context);

  try {
    const claims = event.requestContext.authorizer?.claims as
      | Record<string, string>
      | undefined;
    const userId = getUserId(claims);

    if (!userId) {
      return badRequest("Unauthorized");
    }

    // The Cognito username is needed for AdminDeleteUser.
    // In Cognito with email sign-in, the `sub` is the userId but the
    // username may differ. We read it from the `cognito:username` claim.
    const cognitoUsername =
      claims?.["cognito:username"] ?? claims?.sub ?? userId;

    log.info("Starting account deletion", { userId });

    // 1. Anonymize venue reports (keep data, strip PII)
    await anonymizeReports(userId, log);

    // 2. Delete saved venues
    await deleteSavedVenues(userId, log);

    // 3. Delete S3 profile image
    try {
      await s3.send(
        new DeleteObjectCommand({
          Bucket: PROFILE_IMAGES_BUCKET,
          Key: `profiles/${userId}/avatar.jpg`,
        })
      );
      log.info("Profile image deleted");
    } catch {
      log.warn("Profile image deletion failed (may not exist)");
    }

    // 4. Delete user profile from DynamoDB
    await ddb.send(
      new DeleteCommand({
        TableName: USERS_TABLE,
        Key: { userId },
      })
    );
    log.info("User profile deleted");

    // 5. Delete Cognito user
    if (USER_POOL_ID) {
      try {
        await cognito.send(
          new AdminDeleteUserCommand({
            UserPoolId: USER_POOL_ID,
            Username: cognitoUsername,
          })
        );
        log.info("Cognito user deleted");
      } catch (err) {
        log.error("Cognito user deletion failed", undefined, err);
        // Continue — DynamoDB data is already cleaned up
      }
    }

    log.info("Account deletion complete", { userId });
    return success({ message: "Account deleted" });
  } catch (err) {
    log.error("Account deletion failed", undefined, err);
    return serverError("Failed to delete account");
  }
}

/**
 * Scan VenueReports for this user's reports and replace userId with "deleted-user".
 * Reports have a 2h TTL so the table stays small — a filtered scan is acceptable.
 */
async function anonymizeReports(
  userId: string,
  log: ReturnType<typeof createLogger>
): Promise<void> {
  let lastKey: Record<string, unknown> | undefined;
  let anonymized = 0;

  do {
    const scan = await ddb.send(
      new ScanCommand({
        TableName: REPORTS_TABLE,
        FilterExpression: "userId = :uid",
        ExpressionAttributeValues: { ":uid": userId },
        ProjectionExpression: "venueId, #ts",
        ExpressionAttributeNames: { "#ts": "timestamp" },
        ExclusiveStartKey: lastKey,
      })
    );

    if (scan.Items) {
      for (const item of scan.Items) {
        await ddb.send(
          new UpdateCommand({
            TableName: REPORTS_TABLE,
            Key: {
              venueId: item.venueId,
              timestamp: item.timestamp,
            },
            UpdateExpression: "SET userId = :anon",
            ExpressionAttributeValues: { ":anon": "deleted-user" },
          })
        );
        anonymized++;
      }
    }

    lastKey = scan.LastEvaluatedKey as Record<string, unknown> | undefined;
  } while (lastKey);

  log.info(`Anonymized ${anonymized} reports`);
}

/**
 * Query all saved venues for this user and delete them.
 */
async function deleteSavedVenues(
  userId: string,
  log: ReturnType<typeof createLogger>
): Promise<void> {
  let lastKey: Record<string, unknown> | undefined;
  let deleted = 0;

  do {
    const result = await ddb.send(
      new QueryCommand({
        TableName: SAVED_VENUES_TABLE,
        KeyConditionExpression: "userId = :uid",
        ExpressionAttributeValues: { ":uid": userId },
        ProjectionExpression: "userId, venueId",
        ExclusiveStartKey: lastKey,
      })
    );

    if (result.Items) {
      for (const item of result.Items) {
        await ddb.send(
          new DeleteCommand({
            TableName: SAVED_VENUES_TABLE,
            Key: {
              userId: item.userId,
              venueId: item.venueId,
            },
          })
        );
        deleted++;
      }
    }

    lastKey = result.LastEvaluatedKey as Record<string, unknown> | undefined;
  } while (lastKey);

  log.info(`Deleted ${deleted} saved venues`);
}
