import { processExternalLocation } from '@vietmap/rn_vietmap_tracking_plugin';

/**
 * Replay a GPX track through the SDK.
 *
 * Note this is NOT a port of the Flutter example's `gpx_simulator.dart`. That
 * file is dead code there — nothing imports it, and it never calls the plugin:
 * it fires a UI callback with a hardcoded speed of 2.78 m/s and heading 0. It
 * exercises nothing.
 *
 * This feeds `processExternalLocation`, which the SDK routes into the real
 * tracking pipeline with `isExternalSource: true`, so replayed points are
 * recorded and uploaded exactly like device fixes. That makes it useful for
 * testing a route on a physical device, where `simctl location` and
 * `adb emu geo fix` are unavailable.
 */

export interface GpxWaypoint {
  lat: number;
  lng: number;
  /** Milliseconds since the epoch, when the track recorded one. */
  time?: number;
}

/**
 * Pull waypoints out of a GPX document.
 *
 * Deliberately a regex rather than an XML parser: GPX track points are a flat,
 * attribute-only element, and a parser would be a dependency for one shape.
 * Handles `<trkpt>` and `<rtept>`, with attributes in either order.
 */
export function parseGpx(xml: string): GpxWaypoint[] {
  const points: GpxWaypoint[] = [];
  const pointRe = /<(?:trkpt|rtept)\b([^>]*)>([\s\S]*?)<\/(?:trkpt|rtept)>|<(?:trkpt|rtept)\b([^>]*)\/>/g;

  let match: RegExpExecArray | null;
  while ((match = pointRe.exec(xml)) !== null) {
    const attrs = match[1] ?? match[3] ?? '';
    const body = match[2] ?? '';

    const lat = Number(/\blat\s*=\s*"([^"]+)"/.exec(attrs)?.[1]);
    const lng = Number(/\blon\s*=\s*"([^"]+)"/.exec(attrs)?.[1]);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;

    const timeText = /<time>([^<]+)<\/time>/.exec(body)?.[1];
    const time = timeText ? Date.parse(timeText) : undefined;

    points.push({
      lat,
      lng,
      time: Number.isFinite(time) ? time : undefined,
    });
  }
  return points;
}

const EARTH_RADIUS_M = 6_371_000;
const toRad = (deg: number) => (deg * Math.PI) / 180;

function distanceMeters(a: GpxWaypoint, b: GpxWaypoint): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

function bearingDegrees(a: GpxWaypoint, b: GpxWaypoint): number {
  const dLng = toRad(b.lng - a.lng);
  const y = Math.sin(dLng) * Math.cos(toRad(b.lat));
  const x =
    Math.cos(toRad(a.lat)) * Math.sin(toRad(b.lat)) -
    Math.sin(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.cos(dLng);
  return (((Math.atan2(y, x) * 180) / Math.PI) + 360) % 360;
}

/**
 * The SDK reads a speed at or below 30 as m/s and above it as km/h. A computed
 * speed above 30 m/s — 108 km/h, reachable on a motorway track — would be
 * silently reinterpreted as km/h and land about 3.6x too low.
 *
 * Clamped rather than converted, because converting would hand the SDK a number
 * in the band it reads as m/s anyway. Anything this fast is beyond what the
 * ambiguity can express, so the honest move is to cap and say so.
 */
const MAX_UNAMBIGUOUS_SPEED_MS = 30;

export interface GpxReplayOptions {
  /** Milliseconds between points when the track carries no timestamps. */
  fixedIntervalMs?: number;
  /** Multiplier on recorded time deltas. 2 replays at double speed. */
  rate?: number;
  onProgress?: (sent: number, total: number) => void;
  onDone?: () => void;
  onError?: (message: string) => void;
}

/**
 * Drives one replay. Create, `start()`, and `stop()` when done or unmounting —
 * a replay left running keeps feeding the SDK after its screen has gone.
 */
export class GpxReplay {
  private timer: ReturnType<typeof setTimeout> | null = null;
  private index = 0;
  private running = false;

  constructor(
    private readonly waypoints: GpxWaypoint[],
    private readonly options: GpxReplayOptions = {}
  ) {}

  get isRunning(): boolean {
    return this.running;
  }

  get progress(): { sent: number; total: number } {
    return { sent: this.index, total: this.waypoints.length };
  }

  start(): void {
    if (this.running || this.waypoints.length === 0) return;
    this.running = true;
    this.index = 0;
    void this.sendNext();
  }

  stop(): void {
    this.running = false;
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  private async sendNext(): Promise<void> {
    if (!this.running) return;

    const current = this.waypoints[this.index];
    if (!current) {
      this.running = false;
      this.options.onDone?.();
      return;
    }

    const previous = this.index > 0 ? this.waypoints[this.index - 1] : undefined;
    const rate = this.options.rate && this.options.rate > 0 ? this.options.rate : 1;

    // Speed and heading are derived from the previous point, so the first point
    // has neither — sending zeros is honest there rather than inventing motion.
    let speed = 0;
    let heading = 0;
    if (previous) {
      const metres = distanceMeters(previous, current);
      const elapsedMs =
        previous.time != null && current.time != null
          ? Math.max(1, current.time - previous.time)
          : (this.options.fixedIntervalMs ?? 1000);
      speed = Math.min((metres / elapsedMs) * 1000 * rate, MAX_UNAMBIGUOUS_SPEED_MS);
      heading = bearingDegrees(previous, current);
    }

    try {
      await processExternalLocation({
        lat: current.lat,
        lng: current.lng,
        speed,
        heading,
      });
    } catch (error) {
      this.running = false;
      this.options.onError?.(error instanceof Error ? error.message : String(error));
      return;
    }

    this.index += 1;
    this.options.onProgress?.(this.index, this.waypoints.length);

    const next = this.waypoints[this.index];
    if (!next || !this.running) {
      this.running = false;
      this.options.onDone?.();
      return;
    }

    // Honour the track's own timing when it has any, so a recorded route
    // replays at its real pace rather than a made-up one.
    const gapMs =
      current.time != null && next.time != null
        ? Math.max(0, (next.time - current.time) / rate)
        : (this.options.fixedIntervalMs ?? 1000) / rate;

    this.timer = setTimeout(() => void this.sendNext(), gapMs);
  }
}

/**
 * A short route through central Ho Chi Minh City, with no timestamps, so it
 * replays on the fixed interval. Enough points to cross the SDK's 25m distance
 * floor several times.
 */
export const SAMPLE_GPX = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="rn-vietmap-example">
  <trk><name>Sample</name><trkseg>
    <trkpt lat="10.762622" lon="106.660172" />
    <trkpt lat="10.763500" lon="106.661200" />
    <trkpt lat="10.764400" lon="106.662300" />
    <trkpt lat="10.765300" lon="106.663400" />
    <trkpt lat="10.766200" lon="106.664500" />
    <trkpt lat="10.767100" lon="106.665600" />
    <trkpt lat="10.768000" lon="106.666700" />
    <trkpt lat="10.768900" lon="106.667800" />
  </trkseg></trk>
</gpx>`;
