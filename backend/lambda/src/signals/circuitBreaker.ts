/**
 * Simple in-memory circuit breaker for external API calls.
 *
 * States:
 * - CLOSED: requests flow normally
 * - OPEN: requests are rejected immediately (returns null/fallback)
 * - HALF_OPEN: after cooldown, allows one probe request through
 *
 * Since Lambda instances are ephemeral, each warm instance maintains
 * its own breaker state. This is fine — the goal is to prevent a single
 * Lambda invocation from wasting time on a down service, not global coordination.
 */

export interface CircuitBreakerOptions {
  /** Number of consecutive failures before opening the circuit. */
  failureThreshold: number;
  /** Milliseconds to wait before transitioning from OPEN → HALF_OPEN. */
  cooldownMs: number;
  /** Human-readable name for logging. */
  name: string;
}

type CircuitState = "CLOSED" | "OPEN" | "HALF_OPEN";

export class CircuitBreaker {
  private state: CircuitState = "CLOSED";
  private consecutiveFailures = 0;
  private lastFailureTime = 0;
  private readonly options: CircuitBreakerOptions;

  constructor(options: CircuitBreakerOptions) {
    this.options = options;
  }

  /**
   * Returns true if the request should be allowed through.
   * When OPEN, checks if cooldown has elapsed to transition to HALF_OPEN.
   */
  allowRequest(): boolean {
    if (this.state === "CLOSED") return true;

    if (this.state === "OPEN") {
      const elapsed = Date.now() - this.lastFailureTime;
      if (elapsed >= this.options.cooldownMs) {
        this.state = "HALF_OPEN";
        return true;
      }
      return false;
    }

    // HALF_OPEN: allow one probe request
    return true;
  }

  /** Record a successful request. Resets the breaker to CLOSED. */
  recordSuccess(): void {
    this.consecutiveFailures = 0;
    this.state = "CLOSED";
  }

  /** Record a failed request. Opens the circuit if threshold is reached. */
  recordFailure(): void {
    this.consecutiveFailures++;
    this.lastFailureTime = Date.now();

    if (this.consecutiveFailures >= this.options.failureThreshold) {
      this.state = "OPEN";
    }
  }

  /** Current state for logging/debugging. */
  getState(): CircuitState {
    return this.state;
  }

  /** Whether the circuit is currently open (blocking requests). */
  isOpen(): boolean {
    return this.state === "OPEN" && Date.now() - this.lastFailureTime < this.options.cooldownMs;
  }
}

// Shared breaker instances (per warm Lambda instance)
export const foursquareBreaker = new CircuitBreaker({
  name: "foursquare",
  failureThreshold: 5,
  cooldownMs: 30_000,
});

export const googleBreaker = new CircuitBreaker({
  name: "google",
  failureThreshold: 5,
  cooldownMs: 30_000,
});
