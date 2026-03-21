import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from "aws-lambda";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand } from "@aws-sdk/lib-dynamodb";
import { REPORTS_TABLE, success, badRequest, serverError } from "./shared";
import { createLogger } from "./logger";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

export async function handler(
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> {
  const log = createLogger("getVenueReports", event, context);
  try {
    const venueId = event.pathParameters?.venueId;

    if (!venueId) {
      return badRequest("Missing venueId path parameter");
    }

    log.info("Fetching venue reports", { venueId });

    const result = await ddb.send(
      new QueryCommand({
        TableName: REPORTS_TABLE,
        KeyConditionExpression: "venueId = :vid",
        ExpressionAttributeValues: { ":vid": venueId },
        ScanIndexForward: false, // newest first
        Limit: 10,
      })
    );

    const reports = (result.Items ?? []).map((item) => ({
      reportId: item.reportId,
      userId: item.userId,
      busynessLevel: item.busynessLevel,
      waitMinutes: item.waitMinutes ?? null,
      timestamp: new Date(item.timestamp as number).toISOString(),
      venueName: item.venueName,
      venueType: item.venueType,
    }));

    log.info("Returning reports", { venueId, count: reports.length });
    return success({ venueId, reports });
  } catch (err) {
    log.error("Failed to fetch venue reports", undefined, err);
    return serverError("Failed to fetch venue reports");
  }
}
