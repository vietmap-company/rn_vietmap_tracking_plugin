import type { LocationTrackingConfig } from './types';
import { LIMITS, LOCATION_ACCURACY } from './constants';

/**
 * Validation result interface
 */
export interface ValidationResult {
  isValid: boolean;
  errors: string[];
  warnings: string[];
}

/**
 * Validates location tracking configuration
 * @param config - Configuration to validate
 * @returns ValidationResult
 */
export function validateLocationConfig(config: LocationTrackingConfig): ValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  // Validate interval
  if (!config.intervalMs || typeof config.intervalMs !== 'number') {
    errors.push('intervalMs must be a number');
  } else if (config.intervalMs < LIMITS.MIN_INTERVAL_MS) {
    errors.push(`intervalMs must be at least ${LIMITS.MIN_INTERVAL_MS}ms`);
  } else if (config.intervalMs > LIMITS.MAX_INTERVAL_MS) {
    errors.push(`intervalMs must be at most ${LIMITS.MAX_INTERVAL_MS}ms`);
  } else if (config.intervalMs < 5000) {
    warnings.push('Very frequent updates may impact battery life');
  }

  // Validate distance filter
  if (typeof config.distanceFilter !== 'number') {
    errors.push('distanceFilter must be a number');
  } else if (config.distanceFilter < LIMITS.MIN_DISTANCE_FILTER) {
    errors.push(`distanceFilter must be at least ${LIMITS.MIN_DISTANCE_FILTER}m`);
  } else if (config.distanceFilter > LIMITS.MAX_DISTANCE_FILTER) {
    errors.push(`distanceFilter must be at most ${LIMITS.MAX_DISTANCE_FILTER}m`);
  }

  // Validate accuracy
  if (!config.accuracy || typeof config.accuracy !== 'string') {
    errors.push('accuracy must be a string');
  } else if (!Object.values(LOCATION_ACCURACY).includes(config.accuracy as any)) {
    errors.push(`accuracy must be one of: ${Object.values(LOCATION_ACCURACY).join(', ')}`);
  }

  // Validate background mode
  if (typeof config.backgroundMode !== 'boolean') {
    errors.push('backgroundMode must be a boolean');
  }

  // Validate notification strings (optional)
  if (config.notificationTitle && typeof config.notificationTitle !== 'string') {
    errors.push('notificationTitle must be a string');
  }

  if (config.notificationMessage && typeof config.notificationMessage !== 'string') {
    errors.push('notificationMessage must be a string');
  }

  // Additional warnings
  if (config.backgroundMode && config.intervalMs < 10000) {
    warnings.push('Background tracking with frequent updates may be limited by the OS');
  }

  if (config.accuracy === 'low' && config.distanceFilter < 50) {
    warnings.push('Low accuracy with small distance filter may result in inaccurate filtering');
  }

  return {
    isValid: errors.length === 0,
    errors,
    warnings
  };
}

/**
 * Validates location data
 * @param location - Location data to validate
 * @returns ValidationResult
 */
export function validateLocationData(location: any): ValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  // Check required fields
  if (typeof location.latitude !== 'number') {
    errors.push('latitude must be a number');
  } else if (location.latitude < -90 || location.latitude > 90) {
    errors.push('latitude must be between -90 and 90');
  }

  if (typeof location.longitude !== 'number') {
    errors.push('longitude must be a number');
  } else if (location.longitude < -180 || location.longitude > 180) {
    errors.push('longitude must be between -180 and 180');
  }

  if (typeof location.altitude !== 'number') {
    errors.push('altitude must be a number');
  }

  if (typeof location.accuracy !== 'number') {
    errors.push('accuracy must be a number');
  } else if (location.accuracy < 0) {
    errors.push('accuracy must be positive');
  } else if (location.accuracy > 1000) {
    warnings.push('Location accuracy is very low (>1000m)');
  }

  if (typeof location.speed !== 'number') {
    errors.push('speed must be a number');
  } else if (location.speed < 0) {
    errors.push('speed must be positive');
  }

  if (typeof location.bearing !== 'number') {
    errors.push('bearing must be a number');
  } else if (location.bearing < 0 || location.bearing > 360) {
    errors.push('bearing must be between 0 and 360');
  }

  if (typeof location.timestamp !== 'number') {
    errors.push('timestamp must be a number');
  } else if (location.timestamp <= 0) {
    errors.push('timestamp must be positive');
  }

  return {
    isValid: errors.length === 0,
    errors,
    warnings
  };
}

/**
 * Sanitizes and normalizes location configuration
 * @param config - Raw configuration
 * @returns Normalized configuration
 */
export function normalizeLocationConfig(config: Partial<LocationTrackingConfig>): LocationTrackingConfig {
  return {
    intervalMs: Math.max(LIMITS.MIN_INTERVAL_MS, Math.min(LIMITS.MAX_INTERVAL_MS, config.intervalMs || 5000)),
    distanceFilter: Math.max(LIMITS.MIN_DISTANCE_FILTER, Math.min(LIMITS.MAX_DISTANCE_FILTER, config.distanceFilter || 10)),
    accuracy: Object.values(LOCATION_ACCURACY).includes(config.accuracy as any) ? config.accuracy as any : LOCATION_ACCURACY.HIGH,
    backgroundMode: Boolean(config.backgroundMode),
    notificationTitle: config.notificationTitle || 'GPS Tracking Active',
    notificationMessage: config.notificationMessage || 'Your location is being tracked'
  };
}

/**
 * Checks if location is within valid bounds
 * @param latitude - Latitude value
 * @param longitude - Longitude value
 * @returns True if valid
 */
export function isValidCoordinate(latitude: number, longitude: number): boolean {
  return latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}

/**
 * Checks if location accuracy is acceptable
 * @param accuracy - Accuracy in meters
 * @param threshold - Acceptable threshold (default: 100m)
 * @returns True if acceptable
 */
export function isAcceptableAccuracy(accuracy: number, threshold: number = 100): boolean {
  return accuracy > 0 && accuracy <= threshold;
}

/**
 * Checks if location is reasonable (not obviously invalid)
 * @param location - Location data
 * @returns True if reasonable
 */
export function isReasonableLocation(location: any): boolean {
  // Check if coordinates are not null island (0, 0)
  if (location.latitude === 0 && location.longitude === 0) {
    return false;
  }

  // Check if coordinates are reasonable
  if (!isValidCoordinate(location.latitude, location.longitude)) {
    return false;
  }

  // Check if speed is reasonable (less than 300 km/h)
  if (location.speed > 83.33) { // 300 km/h in m/s
    return false;
  }

  // Check if accuracy is reasonable
  if (!isAcceptableAccuracy(location.accuracy, 5000)) { // 5km threshold
    return false;
  }

  return true;
}
