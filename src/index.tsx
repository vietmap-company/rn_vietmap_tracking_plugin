import { NativeEventEmitter, NativeModules } from 'react-native';
import RnVietmapTrackingPlugin from './NativeRnVietmapTrackingPlugin';
import { validateLocationConfig, normalizeLocationConfig } from './validation';
import type {
  LocationTrackingConfig,
  LocationData,
  TrackingStatus,
  LocationUpdateCallback,
  TrackingStatusCallback,
  PermissionResult,
} from './types';

// Event emitter for location updates
const eventEmitter = new NativeEventEmitter(NativeModules.RnVietmapTrackingPlugin);

export function multiply(a: number, b: number): number {
  return RnVietmapTrackingPlugin.multiply(a, b);
}

/**
 * Request location permissions
 * @returns Promise<PermissionResult> - Permission result with detailed status
 */
export async function requestLocationPermissions(): Promise<PermissionResult> {
  try {
    const result = await RnVietmapTrackingPlugin.requestLocationPermissions();
    return result;
  } catch (error) {
    console.error('Failed to request location permissions:', error);
    throw error;
  }
}

/**
 * Check if location permissions are granted
 * @returns Promise<PermissionResult> - Current permission status
 */
export async function hasLocationPermissions(): Promise<PermissionResult> {
  try {
    const result = await RnVietmapTrackingPlugin.hasLocationPermissions();
    return result;
  } catch (error) {
    console.error('Failed to check location permissions:', error);
    throw error;
  }
}

/**
 * Configure VietmapTrackingSDK with API key and settings
 * @param apiKey - API key for VietmapTrackingSDK
 * @param baseURL - Optional base URL for the API
 * @param autoUpload - Optional auto upload setting (default: true)
 * @returns Promise<boolean> - Success status
 */
export async function configure(apiKey: string, baseURL?: string, autoUpload: boolean = true): Promise<boolean> {
  try {
    const result = await RnVietmapTrackingPlugin.configure(apiKey, baseURL, autoUpload);
    return result;
  } catch (error) {
    console.error('Failed to configure VietmapTrackingSDK:', error);
    throw error;
  }
}

/**
 * Start GPS location tracking with specified configuration
 * @param config - Configuration for location tracking
 * @returns Promise<boolean> - Success status
 */
export async function startLocationTracking(config: LocationTrackingConfig): Promise<boolean> {
  try {
    // Request permissions first
    const permissionStatus = await hasLocationPermissions();
    if (!permissionStatus.granted) {
      const permissionResult = await requestLocationPermissions();
      if (!permissionResult.granted) {
        throw new Error('Location permission denied');
      }
    }

    // Extract parameters from config for native call
    const backgroundMode = config.backgroundMode || false;
    const intervalMs = config.intervalMs || 5000;
    const distanceFilter = config.distanceFilter || 10;

    const result = await RnVietmapTrackingPlugin.startTracking(
      backgroundMode,
      intervalMs,
      false, // forceUpdateBackground default to false
      distanceFilter
    );
    return result === 'success';
  } catch (error) {
    console.error('Failed to start location tracking:', error);
    throw error;
  }
}

/**
 * Stop GPS location tracking
 * @returns Promise<boolean> - Success status
 */
export async function stopLocationTracking(): Promise<boolean> {
  try {
    const result = await RnVietmapTrackingPlugin.stopTracking();
    return result === 'success';
  } catch (error) {
    console.error('Failed to stop location tracking:', error);
    return false;
  }
}

/**
 * Get current location immediately
 * @returns Promise<LocationData> - Current location data
 */
export async function getCurrentLocation(): Promise<LocationData> {
  const location = await RnVietmapTrackingPlugin.getCurrentLocation();
  return location as LocationData;
}

/**
 * Check if location tracking is currently active
 * @returns Promise<boolean> - Tracking status
 */
export async function isTrackingActive(): Promise<boolean> {
  return RnVietmapTrackingPlugin.isTrackingActive();
}

/**
 * Get detailed tracking status
 * @returns Promise<TrackingStatus> - Detailed status information
 */
export async function getTrackingStatus(): Promise<TrackingStatus> {
  const status = await RnVietmapTrackingPlugin.getTrackingStatus();
  return status as TrackingStatus;
}

/**
 * Update tracking configuration while tracking is active
 * @param config - New configuration
 * @returns Promise<boolean> - Success status
 */
export async function updateTrackingConfig(config: LocationTrackingConfig): Promise<boolean> {
  return RnVietmapTrackingPlugin.updateTrackingConfig(config);
}

/**
 * Request always location permissions (required for background tracking)
 * @returns Promise<string> - Permission status
 */
export async function requestAlwaysLocationPermissions(): Promise<string> {
  return RnVietmapTrackingPlugin.requestAlwaysLocationPermissions();
}

/**
 * Subscribe to location updates
 * @param callback - Callback function to receive location updates
 * @returns Subscription object with remove method
 */
export function addLocationUpdateListener(callback: LocationUpdateCallback) {
  return eventEmitter.addListener('onLocationUpdate', callback);
}

/**
 * Subscribe to tracking status changes
 * @param callback - Callback function to receive status updates
 * @returns Subscription object with remove method
 */
export function addTrackingStatusListener(callback: TrackingStatusCallback) {
  return eventEmitter.addListener('onTrackingStatusChanged', callback);
}

/**
 * Create default tracking configuration
 * @param intervalMs - Update interval in milliseconds (default: 5000)
 * @returns LocationTrackingConfig - Default configuration
 */
export function createDefaultConfig(intervalMs: number = 5000): LocationTrackingConfig {
  const config = {
    intervalMs,
    distanceFilter: 10, // 10 meters
    accuracy: 'high' as const,
    backgroundMode: true,
    notificationTitle: 'GPS Tracking Active',
    notificationMessage: 'Your location is being tracked'
  };

  // Validate and normalize config
  const validationResult = validateLocationConfig(config);
  if (!validationResult.isValid) {
    console.warn('Invalid default config:', validationResult.errors);
    return normalizeLocationConfig(config);
  }

  if (validationResult.warnings.length > 0) {
    console.warn('Config warnings:', validationResult.warnings);
  }

  return config;
}

/**
 * Turn on speed alert monitoring (native handles permission checking)
 * @returns Promise<boolean> - Returns true if speed alert turned on successfully, false otherwise
 */
export async function turnOnAlert(): Promise<boolean> {
  try {
    return await RnVietmapTrackingPlugin.turnOnAlert();
  } catch (error) {
    console.error('❌ Failed to turn on speed alert:', error);
    return false;
  }
}

/**
 * Turn off speed alert monitoring
 * @returns Promise<boolean> - Returns true if speed alert turned off successfully, false otherwise
 */
export async function turnOffAlert(): Promise<boolean> {
  try {
    return await RnVietmapTrackingPlugin.turnOffAlert();
  } catch (error) {
    console.error('❌ Failed to turn off speed alert:', error);
    return false;
  }
}

// MARK: - Route and Alert Processing Functions
// Note: Route processing functions are now handled natively.
// Use RnVietmapTrackingPlugin directly for route processing:
// - RnVietmapTrackingPlugin.processRouteData(routeJson)
// - RnVietmapTrackingPlugin.getCurrentRouteInfo()
// - RnVietmapTrackingPlugin.findNearestAlert(latitude, longitude)
// - RnVietmapTrackingPlugin.checkSpeedViolation(currentSpeed)

// Speed alert events are now handled natively with speech synthesis
// No need for JavaScript listeners

// Alias functions for backward compatibility
export const startTracking = startLocationTracking;
export const stopTracking = stopLocationTracking;

// Export utilities and presets
export { TrackingPresets, LocationUtils, TrackingSession } from './utils';

// Export constants
export * from './constants';

// Export validation functions
export * from './validation';

// Export types
export type {
  LocationTrackingConfig,
  LocationData,
  TrackingStatus,
  LocationUpdateCallback,
  TrackingStatusCallback,
};
