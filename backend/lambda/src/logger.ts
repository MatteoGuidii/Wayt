import type { APIGatewayProxyEvent, Context } from "aws-lambda";

// -----------------------------------------------
// Types
// -----------------------------------------------

export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR";

interface LogEntry {
  level: LogLevel;
  handler: string;
  requestId?: string;
  userId?: string;
  message: string;
  data?: Record<string, unknown>;
  error?: { name: string; message: string; stack?: string };
  timestamp: string;
}

export interface Logger {
  debug(message: string, data?: Record<string, unknown>): void;
  info(message: string, data?: Record<string, unknown>): void;
  warn(message: string, data?: Record<string, unknown>): void;
  error(message: string, data: Record<string, unknown> | undefined, err?: unknown): void;
  /** Returns a function that, when called, logs completion with elapsed duration. */
  startTimer(label: string): (data?: Record<string, unknown>) => void;
}

// -----------------------------------------------
// Factory
// -----------------------------------------------

/**
 * Creates a structured JSON logger for a Lambda handler.
 *
 * CloudWatch natively parses single-line JSON, enabling filtering via
 * CloudWatch Insights on any field (handler, level, requestId, userId, etc.).
 *
 * Usage:
 *   const log = createLogger("submitReport", event, context);
 *   log.info("Report submitted", { venueId, busynessLevel });
 *   log.error("DynamoDB write failed", { table: "VenueReports" }, err);
 *
 *   const done = log.startTimer("Handler complete");
 *   // ... work ...
 *   done({ statusCode: 200 });
 */
export function createLogger(
  handler: string,
  event?: APIGatewayProxyEvent,
  context?: Context
): Logger {
  const requestId = context?.awsRequestId;
  const userId = extractUserId(event);

  function emit(
    level: LogLevel,
    message: string,
    data?: Record<string, unknown>,
    err?: unknown
  ): void {
    const entry: LogEntry = {
      level,
      handler,
      message,
      timestamp: new Date().toISOString(),
    };
    if (requestId) entry.requestId = requestId;
    if (userId) entry.userId = userId;
    if (data && Object.keys(data).length > 0) entry.data = data;
    if (err instanceof Error) {
      entry.error = {
        name: err.name,
        message: err.message,
        stack: err.stack,
      };
    }
    // Single-line JSON — CloudWatch parses automatically
    console.log(JSON.stringify(entry));
  }

  return {
    debug: (msg, data) => emit("DEBUG", msg, data),
    info: (msg, data) => emit("INFO", msg, data),
    warn: (msg, data) => emit("WARN", msg, data),
    error: (msg, data, err) => emit("ERROR", msg, data, err),
    startTimer(label: string) {
      const start = Date.now();
      return (data?: Record<string, unknown>) => {
        emit("INFO", label, { ...data, durationMs: Date.now() - start });
      };
    },
  };
}

// -----------------------------------------------
// Helpers
// -----------------------------------------------

function extractUserId(
  event?: APIGatewayProxyEvent
): string | undefined {
  const claims = event?.requestContext?.authorizer?.claims as
    | Record<string, string>
    | undefined;
  return claims?.sub;
}
