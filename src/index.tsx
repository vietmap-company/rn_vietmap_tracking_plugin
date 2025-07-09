import { NativeEventEmitter, NativeModules } from 'react-native';
import RnVietmapTrackingPlugin from './NativeRnVietmapTrackingPlugin';
import { validateLocationConfig, normalizeLocationConfig } from './validation';
import type {
  LocationTrackingConfig,
  LocationData,
  TrackingStatus,
  LocationUpdateCallback,
  TrackingStatusCallback,
  LocationErrorCallback,
  PermissionChangeCallback
} from './types';

// Event emitter for location updates
const eventEmitter = new NativeEventEmitter(NativeModules.RnVietmapTrackingPlugin);

export function multiply(a: number, b: number): number {
  return RnVietmapTrackingPlugin.multiply(a, b);
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
 * Request location permissions
 * @returns Promise<string> - Permission status
 */
export async function requestLocationPermissions(): Promise<string> {
  return RnVietmapTrackingPlugin.requestLocationPermissions();
}

/**
 * Check if location permissions are granted
 * @returns Promise<boolean> - Permission status
 */
export async function hasLocationPermissions(): Promise<boolean> {
  return RnVietmapTrackingPlugin.hasLocationPermissions();
}

/**
 * Request "Always" location permissions for background tracking
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
 * Subscribe to location errors
 * @param callback - Callback function to receive error information
 * @returns Subscription object with remove method
 */
export function addLocationErrorListener(callback: (error: { error: string; code: string; timestamp: number }) => void) {
  return eventEmitter.addListener('onLocationError', callback);
}

/**
 * Subscribe to permission changes
 * @param callback - Callback function to receive permission status changes
 * @returns Subscription object with remove method
 */
export function addPermissionChangeListener(callback: (permission: { status: string; timestamp: number }) => void) {
  return eventEmitter.addListener('onPermissionChanged', callback);
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
 * Enhanced GPS tracking methods using background_location_2 strategy
 */

/**
 * Start GPS tracking with continuous location updates
 * @param backgroundMode - Enable background tracking (requires 'Always' permission)
 * @param intervalMs - Update interval in milliseconds for throttling
 * @param forceUpdateBackground - Force continuous updates bypassing distance filter and OS throttling
 * @param distanceFilter - Minimum distance in meters for location updates (default: 10m)
 * @returns Promise<string> - Status message
 */
export async function startTracking(
  backgroundMode: boolean,
  intervalMs: number = 5000,
  forceUpdateBackground: boolean = false,
  distanceFilter: number = 10
): Promise<string> {
  try {
    console.log('🚀 Starting enhanced tracking with background_location_2 strategy');
    console.log('📤 Background mode:', backgroundMode);
    console.log('📤 Interval:', intervalMs, 'ms');
    console.log('📤 Force update background:', forceUpdateBackground);
    console.log('📤 Distance filter:', distanceFilter, 'm');

    // Request appropriate permissions
    if (backgroundMode) {
      const alwaysPermission = await RnVietmapTrackingPlugin.requestAlwaysLocationPermissions();
      if (alwaysPermission !== 'granted') {
        throw new Error('Background tracking requires "Always" location permission');
      }
    } else {
      const hasPermission = await RnVietmapTrackingPlugin.hasLocationPermissions();
      if (!hasPermission) {
        const permissionResult = await RnVietmapTrackingPlugin.requestLocationPermissions();
        if (permissionResult !== 'granted') {
          throw new Error('Location permission denied');
        }
      }
    }

    return await RnVietmapTrackingPlugin.startTracking(backgroundMode, intervalMs, forceUpdateBackground, distanceFilter);
  } catch (error) {
    console.error('Failed to start enhanced tracking:', error);
    throw error;
  }
}

/**
 * Stop GPS tracking
 * @returns Promise<string> - Status message
 */
export async function stopTracking(): Promise<string> {
  try {
    console.log('🛑 Stopping enhanced tracking');
    return await RnVietmapTrackingPlugin.stopTracking();
  } catch (error) {
    console.error('Failed to stop enhanced tracking:', error);
    throw error;
  }
}

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
  LocationErrorCallback,
  PermissionChangeCallback
};
