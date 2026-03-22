import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  QueryCommand,
  PutCommand,
  DeleteCommand,
  GetCommand,
  BatchGetCommand,
} from "@aws-sdk/lib-dynamodb";
import { neighborhood } from "./geohash";

// -----------------------------------------------
// Table references
// -----------------------------------------------

export const SIGNALS_TABLE = process.env.SIGNALS_TABLE!;
export const REPORTS_TABLE = process.env.REPORTS_TABLE!;

// -----------------------------------------------
// Shared DynamoDB Document Client
// -----------------------------------------------

const rawClient = new DynamoDBClient({});
export const ddb = DynamoDBDocumentClient.from(rawClient);

// -----------------------------------------------
// Key builders
// -----------------------------------------------

export function venueKey(venueId: string) {
  return `VENUE#${venueId}`;
}

export function signalSK(sourceId: string, timestamp: number) {
  return `SIGNAL#${sourceId}#${timestamp}`;
}

export function fusedSK() {
  return "FUSED#CURRENT";
}

export function mappingSK(provider: string) {
  return `MAP#${provider}`;
}

export function activeAreaPK(geohash: string) {
  return `AREA#${geohash}`;
}

// -----------------------------------------------
// GSI query helper
// -----------------------------------------------

const GEOHASH_INDEX = "GeohashIndex";

/**
 * Query the GeohashIndex GSI for items in a single geohash cell
 * whose geoSK begins with the given prefix.
 */
export async function queryByGeohash(
  geohash5: string,
  skPrefix: string
): Promise<Record<string, unknown>[]> {
  const result = await ddb.send(
    new QueryCommand({
      TableName: SIGNALS_TABLE,
      IndexName: GEOHASH_INDEX,
      KeyConditionExpression: "geohash = :gh AND begins_with(geoSK, :prefix)",
      ExpressionAttributeValues: {
        ":gh": geohash5,
        ":prefix": skPrefix,
      },
    })
  );
  return (result.Items ?? []) as Record<string, unknown>[];
}

/**
 * Query all FUSED# items across the 9-cell geohash neighborhood
 * around a lat/lng point. Returns raw DynamoDB items.
 */
export async function queryNearbyFused(
  lat: number,
  lng: number
): Promise<Record<string, unknown>[]> {
  const cells = neighborhood(lat, lng);
  const results = await Promise.all(
    cells.map((cell) => queryByGeohash(cell, "FUSED#"))
  );
  return results.flat();
}

// -----------------------------------------------
// Convenience wrappers
// -----------------------------------------------

export async function getItem(pk: string, sk: string): Promise<Record<string, unknown> | undefined> {
  const result = await ddb.send(
    new GetCommand({
      TableName: SIGNALS_TABLE,
      Key: { PK: pk, SK: sk },
    })
  );
  return result.Item as Record<string, unknown> | undefined;
}

export async function putItem(item: Record<string, unknown>): Promise<void> {
  await ddb.send(
    new PutCommand({
      TableName: SIGNALS_TABLE,
      Item: item,
    })
  );
}

export async function deleteItem(pk: string, sk: string): Promise<void> {
  await ddb.send(
    new DeleteCommand({
      TableName: SIGNALS_TABLE,
      Key: { PK: pk, SK: sk },
    })
  );
}

/**
 * Query items by PK with an SK prefix filter.
 */
export async function queryByPK(
  pk: string,
  skPrefix: string
): Promise<Record<string, unknown>[]> {
  const result = await ddb.send(
    new QueryCommand({
      TableName: SIGNALS_TABLE,
      KeyConditionExpression: "PK = :pk AND begins_with(SK, :prefix)",
      ExpressionAttributeValues: {
        ":pk": pk,
        ":prefix": skPrefix,
      },
    })
  );
  return (result.Items ?? []) as Record<string, unknown>[];
}

/**
 * Batch-check which venue IDs have a specific SK present and unexpired.
 * Returns the set of venue IDs that have a valid (non-expired) item.
 * Processes in chunks of 100 (DynamoDB BatchGetItem limit).
 */
export async function batchCheckExists(
  venueIds: string[],
  sk: string
): Promise<Set<string>> {
  const found = new Set<string>();
  const nowSeconds = Math.floor(Date.now() / 1000);

  // DynamoDB BatchGetItem limit is 100 keys per request
  for (let i = 0; i < venueIds.length; i += 100) {
    const chunk = venueIds.slice(i, i + 100);
    const keys = chunk.map((id) => ({ PK: venueKey(id), SK: sk }));

    const result = await ddb.send(
      new BatchGetCommand({
        RequestItems: {
          [SIGNALS_TABLE]: { Keys: keys },
        },
      })
    );

    const items = result.Responses?.[SIGNALS_TABLE] ?? [];
    for (const item of items) {
      const ttl = item.ttl as number | undefined;
      if (!ttl || ttl >= nowSeconds) {
        // Extract venueId from PK (format: "VENUE#venueId")
        const pk = item.PK as string;
        found.add(pk.replace("VENUE#", ""));
      }
    }
  }

  return found;
}
