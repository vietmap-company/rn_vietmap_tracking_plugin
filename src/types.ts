/**
 * Tracking configuration.
 *
 * `intervalMs` and `distanceFilter` pick the SDK's trigger mode between them:
 *
 * | supplied          | mode                                             |
 * |-------------------|--------------------------------------------------|
 * | intervalMs only   | timer — a fix every intervalMs, stationary or not |
 * | distanceFilter only | displacement — a fix per distanceFilter metres  |
 * | both              | the SDK gives the timer priority and **ignores** the distance gate |
 * | neither           | the SDK's own defaults: 10s timer, 25m floor     |
 *
 * So omit the one you do not want. Passing `0` is not the same thing — it is a
 * value, and the SDK clamps it up to its floor.
 *
 * The SDK enforces floors natively and silently: `intervalMs` is raised to
 * 5000 and `distanceFilter` to 25. Intervals in the 5-10s band also have their
 * uploads coalesced to a single 10s cadence to avoid server rate limiting; GPS
 * sampling is unaffected.
 */
export interface LocationTrackingConfig {
  /** Milliseconds between updates. Omit for distance-driven or SDK-default tracking. */
  intervalMs?: number;
  /** Metres between updates. Omit for timer-driven or SDK-default tracking. */
  distanceFilter?: number;
  /** Desired accuracy. */
  accuracy?: 'high' | 'medium' | 'low';
  /** Keep tracking in the background. Defaults to true. */
  backgroundMode?: boolean;
  /** Foreground service notification title (Android). */
  notificationTitle?: string;
  /** Foreground service notification message (Android). */
  notificationMessage?: string;
  /**
   * Identity written into the upload payload as userId. The SDK refuses to
   * start tracking without it.
   */
  userId?: string;
  /** Vehicle identity written into the upload payload. Optional. */
  vehicleId?: string;
  /**
   * Let mock and simulated locations through. Defaults to true, matching the
   * Flutter plugin.
   *
   * The SDK inspects CLLocationSourceInformation (iOS 15+) and the Android mock
   * provider flag, and when this is false it drops every simulated fix before
   * tracking sees it. That silently empties the upload batch on a simulator or
   * emulator, where every fix is simulated.
   *
   * Set it false in production to turn the SDK's fake GPS detection on, and
   * pair it with setFakeGPSPolicy() to choose what happens on a detection.
   */
  allowMockLocation?: boolean;
  /**
   * Derive speed from distance over time when the OS omits it — network and
   * fused fixes on some Android builds report 0 or -1. Defaults to true.
   */
  enableSpeedFallback?: boolean;
  /** Opt in to battery-aware cadence. Defaults to false. */
  enableSmartBattery?: boolean;
  /** Preset used when enableSmartBattery is true. */
  smartBatteryPreset?: SmartBatteryPreset;
}

export type SmartBatteryPreset = 'navigation' | 'general' | 'batterySaver';

export type FakeGpsPolicy = 'skip' | 'warn' | 'stopTracking' | 'logToServer';

export type AuthMode = 'header' | 'queryParam';

/**
 * A fake GPS detection.
 *
 * Debounced by the SDK to at most one per 30 seconds, on both platforms — the
 * same gate that limits the notification, so this event is throttled too, not
 * only the banner.
 */
export interface FakeGpsEvent {
  lat: number;
  lng: number;
  /**
   * Milliseconds since the epoch, like every other timestamp in this API. The
   * iOS SDK reports seconds here and the bridge converts.
   *
   * Note the Flutter plugin normalises to seconds instead, so the two plugins
   * differ on this one field. The SDK-level behaviour they share — detection,
   * debounce, policy — is identical.
   */
  timestamp: number;
  /** Always true: the SDK only reports the first detection in each 30s window. */
  isFirstDetection?: boolean;
  /** iOS only: 'simulatedBySoftware' or 'producedByAccessory'. */
  reason?: string;
}

/**
 * Tracking was interrupted, or recovered.
 *
 * Do **not** stop and restart tracking in response. The SDK raises this from
 * GPS silence, so a restart only costs a fresh first fix.
 */
export interface TrackingInterruptedEvent {
  reason: TrackingInterruptedReason;
  recovered: boolean;
  isInBackground: boolean;
  secondsSinceLastFix: number;
}

export type TrackingInterruptedReason =
  | 'locationUnavailable'
  | 'providerDisabled'
  | 'paused'
  | 'authDowngraded'
  | 'authDenied'
  | 'locationServicesOff'
  | 'permissionRevoked'
  | 'staleNoUpdates';

export interface TrackingHealthStatus {
  isTracking: boolean;
  hasLocationPermission: boolean;
  hasBackgroundPermission: boolean;
  /** Milliseconds since tracking started, or 0 when not tracking. */
  trackingDuration: number;
  /** Milliseconds since the last fix, or -1 when none has arrived. */
  timeSinceLastUpdate: number;
  isInitialized: boolean;
  /** Milliseconds since the epoch, or absent when no fix has arrived. */
  lastLocationUpdate?: number;
  timestamp: number;
  /**
   * The native SDK's own diagnostics, passed through untouched.
   *
   * iOS only, and its shape is the SDK's rather than this plugin's — CoreLocation
   * details such as `allowsBackgroundLocationUpdates`, `backgroundTaskActive` and
   * `desiredAccuracy`, which have no Android equivalent. Useful when debugging
   * why iOS stopped delivering fixes; do not build a feature on it.
   */
  raw?: Record<string, unknown>;
}

/** One row of server-side history, as returned by getTrackingHistory. */
export interface GpsLocation {
  latitude: number;
  longitude: number;
  speed: number;
  heading: number;
  timestamp: number;
  userId?: string;
  vehicleId?: string;
  accuracy?: number;
}

export interface CacheLimits {
  /** 0 keeps the SDK default: 5000 on Android, 10000 on iOS. */
  maxRecords: number;
  /** 0 keeps the SDK default of 50MB. */
  maxDbSizeBytes: number;
  /** 0 keeps the SDK default of 50. */
  batchSize: number;
}

export interface LocationData {
  latitude: number;
  longitude: number;
  altitude: number;
  accuracy: number;
  speed: number;
  bearing: number;
  timestamp: number;
}

export interface TrackingStatus {
  isTracking: boolean;
  lastLocationUpdate?: number;
  trackingDuration: number;
}

export type LocationUpdateCallback = (location: LocationData) => void;
export type TrackingStatusCallback = (status: TrackingStatus) => void;

// Route and Alert Types
export interface RouteLink {
  id: number;
  direction: number;
  startLat: number;
  startLon: number;
  endLat: number;
  endLon: number;
  distance: number;
  speedLimits: number[][];
}

export interface RouteAlert {
  type: number;
  subtype?: number;
  speedLimit?: number;
}

export interface PermissionResult {
  granted: boolean;
  status: 'granted' | 'denied' | 'not_granted';
  fineLocation?: boolean;
  coarseLocation?: boolean;
  backgroundLocation?: boolean;
}

export interface ProcessedRouteData {
  links: RouteLink[];
  alerts: RouteAlert[];
  offset: any[];
  totalLinks: number;
  totalAlerts: number;
}

export interface NearestAlertResult {
  nearestLinkIndex: number;
  distanceToLink: number;
  alerts: RouteAlert[];
}

export interface SpeedViolationResult {
  isViolation: boolean;
  currentSpeed: number;
  speedLimit?: number;
  excess: number;
  alertInfo?: RouteAlert;
}

// Speed alerts are now handled natively with speech synthesis
// No need for JavaScript event types
