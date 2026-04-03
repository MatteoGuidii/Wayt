import { APIGatewayProxyResult } from "aws-lambda";

// -----------------------------------------------
// Environment
// -----------------------------------------------

export const USERS_TABLE = process.env.USERS_TABLE!;
export const PROFILE_IMAGES_BUCKET = process.env.PROFILE_IMAGES_BUCKET!;
export const SAVED_VENUES_TABLE = process.env.SAVED_VENUES_TABLE!;
export const USER_POOL_ID = process.env.USER_POOL_ID ?? "";

// -----------------------------------------------
// Report TTL: 2 hours
// -----------------------------------------------

export const REPORT_TTL_SECONDS = 2 * 60 * 60;
export const REPORT_COOLDOWN_SECONDS = 30 * 60;
/** Max distance (meters) between user and venue for a report to be accepted. */
export const REPORT_MAX_DISTANCE_M = 300;
/** Max reports a single user can submit per calendar day. */
export const DAILY_REPORT_CAP = 30;

// -----------------------------------------------
// Trust Score
// -----------------------------------------------

export const DEFAULT_TRUST_SCORE = 0.5;
export const NEW_ACCOUNT_TRUST_SCORE = 0.3;
export const NEW_ACCOUNT_THRESHOLD_MS = 24 * 60 * 60 * 1000;
export const TRUST_CORROBORATION_REWARD = 0.03;
export const TRUST_OUTLIER_PENALTY = 0.06;
export const TRUST_FLOOR = 0.1;
export const TRUST_CAP = 1.0;

// -----------------------------------------------
// Velocity Check
// -----------------------------------------------

/** Max reports across all venues within the velocity window before rejection. */
export const VELOCITY_MAX_REPORTS = 8;
export const VELOCITY_WINDOW_MS = 10 * 60 * 1000;

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
  timezone?: string;
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

export interface SaveVenueBody {
  venueId: string;
  venueName: string;
  categoryRaw: string;
  lat: number;
  lng: number;
  address?: string;
}

// -----------------------------------------------
// Response Helpers
// -----------------------------------------------

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
  "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
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

export function tooManyRequests(body: unknown): APIGatewayProxyResult {
  return {
    statusCode: 429,
    headers: corsHeaders,
    body: JSON.stringify(body),
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

// -----------------------------------------------
// ISO Week Helper
// -----------------------------------------------

/** Returns an ISO week key like "2026-W14". */
export function getISOWeekKey(date: Date): string {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNum = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(weekNum).padStart(2, "0")}`;
}
