import { APIGatewayProxyResult } from "aws-lambda";

// -----------------------------------------------
// Environment
// -----------------------------------------------

export const REPORTS_TABLE = process.env.REPORTS_TABLE!;
export const USERS_TABLE = process.env.USERS_TABLE!;
export const PROFILE_IMAGES_BUCKET = process.env.PROFILE_IMAGES_BUCKET!;

// -----------------------------------------------
// Report TTL: 2 hours
// -----------------------------------------------

export const REPORT_TTL_SECONDS = 2 * 60 * 60;

// -----------------------------------------------
// Types
// -----------------------------------------------

export interface SubmitReportBody {
  venueId: string;
  busynessLevel: number;
  waitMinutes?: number;
  venueName: string;
  venueType: string;
  lat: number;
  lng: number;
}

export interface VenueReportSummary {
  venueId: string;
  avgBusyness: number;
  reportCount: number;
  lastReportedAt: string;
  avgWaitMinutes?: number;
}

export interface ReportItem {
  venueId: string;
  timestamp: number;
  reportId: string;
  userId: string;
  busynessLevel: number;
  waitMinutes?: number;
  venueName: string;
  venueType: string;
  lat: number;
  lng: number;
  ttl: number;
}

// -----------------------------------------------
// Response Helpers
// -----------------------------------------------

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
  "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS",
};

export function success(body: unknown): APIGatewayProxyResult {
  return {
    statusCode: 200,
    headers: corsHeaders,
    body: JSON.stringify(body),
  };
}

export function created(body: unknown): APIGatewayProxyResult {
  return {
    statusCode: 201,
    headers: corsHeaders,
    body: JSON.stringify(body),
  };
}

export function badRequest(message: string): APIGatewayProxyResult {
  return {
    statusCode: 400,
    headers: corsHeaders,
    body: JSON.stringify({ error: message }),
  };
}

export function serverError(message: string): APIGatewayProxyResult {
  return {
    statusCode: 500,
    headers: corsHeaders,
    body: JSON.stringify({ error: message }),
  };
}

// -----------------------------------------------
// Auth Helper
// -----------------------------------------------

export function getUserId(
  claims: Record<string, string> | undefined
): string | null {
  return claims?.sub ?? null;
}

// -----------------------------------------------
// Geo Helper
// -----------------------------------------------

/** Approximate distance in meters between two lat/lng points. */
export function haversineDistance(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6_371_000; // Earth radius in meters
  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;

  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
