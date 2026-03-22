// Geohash utilities wrapping ngeohash.
// Precision 5 gives ~4.9km x 4.9km cells — ideal for nearby venue queries.

// ngeohash has no reliable @types, so we declare what we use.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const ngeohash = require("ngeohash") as {
  encode: (lat: number, lng: number, precision?: number) => string;
  decode: (hash: string) => { latitude: number; longitude: number };
  neighbors: (hash: string) => string[];
};

const DEFAULT_PRECISION = 5;

/** Encode lat/lng to a geohash string at the given precision. */
export function encode(lat: number, lng: number, precision = DEFAULT_PRECISION): string {
  return ngeohash.encode(lat, lng, precision);
}

/** Decode a geohash to its center lat/lng. */
export function decode(hash: string): { latitude: number; longitude: number } {
  return ngeohash.decode(hash);
}

/** Return the 8 adjacent geohash cells surrounding the given hash. */
export function neighbors(hash: string): string[] {
  return ngeohash.neighbors(hash);
}

/**
 * Return the center geohash plus its 8 neighbors — the 9-cell neighborhood
 * needed for a radius query (covers ~15km x 15km at precision 5).
 */
export function neighborhood(lat: number, lng: number, precision = DEFAULT_PRECISION): string[] {
  const center = encode(lat, lng, precision);
  return [center, ...neighbors(center)];
}
