/**
 * Shared venue matching utilities used by both Foursquare and Google Places integrations.
 */

/** Max distance (meters) to accept a venue match.
 * 300m accounts for coordinate disagreements between providers,
 * especially for venues in malls, plazas, or multi-building complexes. */
export const MATCH_MAX_DISTANCE_M = 300;

/** Minimum combined score to accept a venue match.
 * 0.2 allows partial name matches (e.g., "Cafe Wandr" vs "Wandr Café"). */
export const MATCH_MIN_SCORE = 0.2;

/** Noise words stripped before comparing venue names. */
export const NOISE_WORDS = new Set([
  "the", "a", "an", "and", "&", "of", "at", "in", "on",
  "restaurant", "restaurants", "bar", "bars", "cafe", "café",
  "grill", "kitchen", "lounge", "pub", "bakery", "bistro",
  "eatery", "diner", "tavern", "steakhouse", "pizzeria",
]);

/**
 * Compute name similarity between two venue names using Jaccard index.
 * Returns 0.0–1.0 where 1.0 is identical token sets.
 */
export function nameSimilarity(a: string, b: string): number {
  const tokenize = (s: string): Set<string> => {
    const tokens = s.toLowerCase().replace(/['\u2019`]/g, "").split(/[\s\-_,.:;!?&()/]+/).filter(Boolean);
    return new Set(tokens.filter((t) => !NOISE_WORDS.has(t)));
  };

  const setA = tokenize(a);
  const setB = tokenize(b);

  if (setA.size === 0 && setB.size === 0) return 1.0;
  if (setA.size === 0 || setB.size === 0) return 0.0;

  let intersection = 0;
  for (const token of setA) {
    if (setB.has(token)) intersection++;
  }

  const union = new Set([...setA, ...setB]).size;
  return intersection / union;
}

/**
 * Convert a UTC timestamp to local day-of-week and minutes-since-midnight using Intl.
 * Returns JS convention: 0=Sunday, 1=Monday, ..., 6=Saturday.
 */
export function getLocalTime(nowMs: number, timezone: string): { localDay: number; localMinutes: number } {
  try {
    const fmt = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      hour: "numeric",
      minute: "numeric",
      weekday: "short",
      hourCycle: "h23",
    });
    const parts = fmt.formatToParts(new Date(nowMs));
    const hour = parseInt(parts.find((p) => p.type === "hour")?.value ?? "0", 10);
    const minute = parseInt(parts.find((p) => p.type === "minute")?.value ?? "0", 10);
    const weekday = parts.find((p) => p.type === "weekday")?.value ?? "";
    const dayMap: Record<string, number> = {
      Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6,
    };
    return { localDay: dayMap[weekday] ?? 0, localMinutes: hour * 60 + minute };
  } catch {
    // Invalid timezone — fall back to UTC
    const d = new Date(nowMs);
    return { localDay: d.getUTCDay(), localMinutes: d.getUTCHours() * 60 + d.getUTCMinutes() };
  }
}
