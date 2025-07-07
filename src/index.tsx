import { NativeEventEmitter, NativeModules } from 'react-native';
import RnVietmapTrackingPlugin from './NativeRnVietmapTrackingPlugin';
import { validateLocationConfig, normalizeLocationConfig } from './validation';
import type {
  LocationTrackingConfig,
  LocationData,
  TrackingStatus,
  LocationUpdateCallback,
  TrackingStatusCallback
} from './types';

// Event emitter for location updates
const eventEmitter = new NativeEventEmitter(NativeModules.RnVietmapTrackingPlugin);

export function multiply(a: number, b: number): number {
  return RnVietmapTrackingPlugin.multiply(a, b);
}

/**
 * Start GPS location tracking with specified configuration
 * @param config - Configuration for location tracking
 * @returns Promise<boolean> - Success status
 */
export async function startLocationTracking(config: LocationTrackingConfig): Promise<boolean> {
  try {
    // Request permissions first
    const hasPermission = await RnVietmapTrackingPlugin.hasLocationPermissions();
    if (!hasPermission) {
      const permissionResult = await RnVietmapTrackingPlugin.requestLocationPermissions();
      if (permissionResult !== 'granted') {
        throw new Error('Location permission denied');
      }
    }

    return await RnVietmapTrackingPlugin.startLocationTracking(config);
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
  return RnVietmapTrackingPlugin.stopLocationTracking();
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
  TrackingStatusCallback
};
