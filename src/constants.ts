import type {
  LocationTrackingConfig,
  FakeGpsPolicy,
  TrackingInterruptedReason,
  SmartBatteryPreset,
} from './types';

/**
 * Tracking presets, ported from the Flutter plugin's TrackingPresets.
 *
 * Every preset drives **one** trigger, never both: the interval entries leave
 * `distanceFilter` unset and the `_DISTANCE` entries leave `intervalMs` unset.
 * Supplying both would make the SDK favour the timer and ignore the distance
 * gate, which is how a distance preset silently becomes a timer.
 *
 * The values respect the floors the SDK enforces natively: 5000ms and 25m.
 * The previous values here (1000ms / 5m for NAVIGATION) sat below both and were
 * silently clamped, so the preset never did what it said.
 */
export const TRACKING_PRESETS = {
  /** Turn-by-turn navigation and live vehicle tracking. A fix every 5s. */
  NAVIGATION: {
    intervalMs: 5000,
    accuracy: 'high',
    backgroundMode: true,
    notificationTitle: 'Navigation Active',
    notificationMessage: 'Tracking your route',
  } satisfies LocationTrackingConfig,

  /** Outdoor fitness. A fix every 10s. */
  FITNESS: {
    intervalMs: 10000,
    accuracy: 'high',
    backgroundMode: true,
    notificationTitle: 'Fitness Tracking',
    notificationMessage: 'Recording your workout',
  } satisfies LocationTrackingConfig,

  /** Fleet and delivery tracking. A fix every 30s. */
  GENERAL: {
    intervalMs: 30000,
    accuracy: 'medium',
    backgroundMode: true,
    notificationTitle: 'Location Tracking',
    notificationMessage: 'Tracking your location',
  } satisfies LocationTrackingConfig,

  /** Slow-moving assets. A fix every 5 minutes. */
  BATTERY_SAVER: {
    intervalMs: 300000,
    accuracy: 'low',
    backgroundMode: true,
    notificationTitle: 'Background Tracking',
    notificationMessage: 'Tracking with battery optimization',
  } satisfies LocationTrackingConfig,

  /** A fix per 25m moved — the densest the SDK's distance floor allows. */
  NAVIGATION_DISTANCE: {
    distanceFilter: 25,
    accuracy: 'high',
    backgroundMode: true,
    notificationTitle: 'Navigation Active',
    notificationMessage: 'Tracking your route',
  } satisfies LocationTrackingConfig,

  /** A fix per 50m moved. */
  FITNESS_DISTANCE: {
    distanceFilter: 50,
    accuracy: 'high',
    backgroundMode: true,
    notificationTitle: 'Fitness Tracking',
    notificationMessage: 'Recording your workout',
  } satisfies LocationTrackingConfig,

  /** A fix per 70m moved. */
  GENERAL_DISTANCE: {
    distanceFilter: 70,
    accuracy: 'medium',
    backgroundMode: true,
    notificationTitle: 'Location Tracking',
    notificationMessage: 'Tracking your location',
  } satisfies LocationTrackingConfig,

  /** A fix per 120m moved. Best conservation for parked or slow assets. */
  BATTERY_SAVER_DISTANCE: {
    distanceFilter: 120,
    accuracy: 'low',
    backgroundMode: true,
    notificationTitle: 'Background Tracking',
    notificationMessage: 'Tracking with battery optimization',
  } satisfies LocationTrackingConfig,
};

/**
 * Defer the cadence to the SDK: neither trigger is set, so it runs its own
 * defaults — currently a 10s timer with a 25m floor. Restating those numbers
 * here would give them a second home to drift from.
 */
export const SDK_DEFAULT_CONFIG: LocationTrackingConfig = {
  backgroundMode: true,
  notificationTitle: 'GPS Tracking Active',
  notificationMessage: 'Your location is being tracked',
};

/** Floors the SDK applies natively. Values below these are raised in silence. */
export const SDK_FLOORS = {
  MIN_INTERVAL_MS: 5000,
  MIN_DISTANCE_FILTER_M: 25,
};

/** What the SDK does on a fake GPS detection, once detection is on. */
export const FAKE_GPS_POLICIES: Record<string, FakeGpsPolicy> = {
  /** Detect and report, change nothing. The SDK default. */
  SKIP: 'skip',
  /** Also raise a local notification. */
  WARN: 'warn',
  /** Halt tracking. */
  STOP_TRACKING: 'stopTracking',
  /** Report the detection to the backend. */
  LOG_TO_SERVER: 'logToServer',
};

/** Reasons carried by onTrackingInterrupted. */
export const TRACKING_INTERRUPTED_REASONS: Record<string, TrackingInterruptedReason> = {
  LOCATION_UNAVAILABLE: 'locationUnavailable',
  PROVIDER_DISABLED: 'providerDisabled',
  PAUSED: 'paused',
  AUTH_DOWNGRADED: 'authDowngraded',
  AUTH_DENIED: 'authDenied',
  LOCATION_SERVICES_OFF: 'locationServicesOff',
  PERMISSION_REVOKED: 'permissionRevoked',
  STALE_NO_UPDATES: 'staleNoUpdates',
};

/** Smart battery presets and the interval each maps to. */
export const SMART_BATTERY_PRESETS: Record<string, SmartBatteryPreset> = {
  NAVIGATION: 'navigation',
  GENERAL: 'general',
  BATTERY_SAVER: 'batterySaver',
};

/**
 * Interval each smart battery preset applies, in milliseconds. These must stay
 * in step with TRACKING_PRESETS above; the native side reads the preset name
 * and derives the same numbers.
 */
export const SMART_BATTERY_INTERVALS_MS: Record<SmartBatteryPreset, number> = {
  navigation: 5000,
  general: 30000,
  batterySaver: 300000,
};

/** A zero in configureCacheLimits keeps the SDK's own value for that field. */
export const KEEP_SDK_CACHE_DEFAULT = 0;

/**
 * Error codes for location tracking
 */
export const LOCATION_ERROR_CODES = {
  PERMISSION_DENIED: 'PERMISSION_DENIED',
  LOCATION_UNAVAILABLE: 'LOCATION_UNAVAILABLE',
  TIMEOUT: 'TIMEOUT',
  NETWORK_ERROR: 'NETWORK_ERROR',
  INVALID_CONFIG: 'INVALID_CONFIG',
  SERVICE_UNAVAILABLE: 'SERVICE_UNAVAILABLE',
  NOT_TRACKING: 'NOT_TRACKING',
  ALREADY_TRACKING: 'ALREADY_TRACKING'
};

/**
 * Location accuracy levels
 */
export const LOCATION_ACCURACY = {
  HIGH: 'high' as const,
  MEDIUM: 'medium' as const,
  LOW: 'low' as const
};

/**
 * Permission status
 */
export const PERMISSION_STATUS = {
  GRANTED: 'granted',
  DENIED: 'denied',
  RESTRICTED: 'restricted',
  PENDING: 'pending'
};

/**
 * Default configuration values
 */
export const DEFAULT_CONFIG = {
  INTERVAL_MS: 5000,
  // The SDK clamps this up to 25; 10 was never reachable.
  DISTANCE_FILTER: 25,
  ACCURACY: LOCATION_ACCURACY.HIGH,
  BACKGROUND_MODE: true,
  NOTIFICATION_TITLE: 'GPS Tracking Active',
  NOTIFICATION_MESSAGE: 'Your location is being tracked'
};

/**
 * Limits and constraints
 */
export const LIMITS = {
  // Below the SDK floors these are accepted and then silently raised.
  // See SDK_FLOORS for what actually takes effect.
  MIN_INTERVAL_MS: 5000,
  MAX_INTERVAL_MS: 3600000, // 1 hour
  MIN_DISTANCE_FILTER: 25,
  MAX_DISTANCE_FILTER: 1000, // 1000 meters
  MAX_LOCATION_HISTORY: 1000 // Maximum locations to keep in history
};
