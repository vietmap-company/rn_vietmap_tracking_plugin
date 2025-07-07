/**
 * Common tracking presets for different use cases
 */
export const TRACKING_PRESETS = {
  /**
   * High precision tracking for navigation apps
   * Updates every 1 second with high accuracy
   */
  NAVIGATION: {
    intervalMs: 1000,
    distanceFilter: 5,
    accuracy: 'high' as const,
    backgroundMode: true,
    notificationTitle: 'Navigation Active',
    notificationMessage: 'Tracking your route'
  },

  /**
   * Fitness tracking configuration
   * Updates every 5 seconds with high accuracy
   */
  FITNESS: {
    intervalMs: 5000,
    distanceFilter: 10,
    accuracy: 'high' as const,
    backgroundMode: true,
    notificationTitle: 'Fitness Tracking',
    notificationMessage: 'Recording your workout'
  },

  /**
   * General location tracking
   * Updates every 30 seconds with medium accuracy
   */
  GENERAL: {
    intervalMs: 30000,
    distanceFilter: 50,
    accuracy: 'medium' as const,
    backgroundMode: true,
    notificationTitle: 'Location Tracking',
    notificationMessage: 'Tracking your location'
  },

  /**
   * Battery optimized tracking
   * Updates every 5 minutes with low accuracy
   */
  BATTERY_SAVER: {
    intervalMs: 300000, // 5 minutes
    distanceFilter: 100,
    accuracy: 'low' as const,
    backgroundMode: true,
    notificationTitle: 'Background Tracking',
    notificationMessage: 'Tracking with battery optimization'
  }
};

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
  DISTANCE_FILTER: 10,
  ACCURACY: LOCATION_ACCURACY.HIGH,
  BACKGROUND_MODE: true,
  NOTIFICATION_TITLE: 'GPS Tracking Active',
  NOTIFICATION_MESSAGE: 'Your location is being tracked'
};

/**
 * Limits and constraints
 */
export const LIMITS = {
  MIN_INTERVAL_MS: 1000, // 1 second
  MAX_INTERVAL_MS: 3600000, // 1 hour
  MIN_DISTANCE_FILTER: 0, // 0 meters
  MAX_DISTANCE_FILTER: 1000, // 1000 meters
  MAX_LOCATION_HISTORY: 1000 // Maximum locations to keep in history
};
