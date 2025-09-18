import { Platform } from 'react-native';
import type { LocationTrackingConfig } from './types';

/**
 * Predefined tracking configurations for common use cases
 */
export const TrackingPresets = {
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
 * Utility functions for location tracking
 */
export class LocationUtils {
  /**
   * Calculate distance between two points using Haversine formula
   * @param lat1 - Latitude of first point
   * @param lon1 - Longitude of first point
   * @param lat2 - Latitude of second point
   * @param lon2 - Longitude of second point
   * @returns Distance in meters
   */
  static calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371000; // Earth's radius in meters
    const dLat = this.toRadians(lat2 - lat1);
    const dLon = this.toRadians(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(this.toRadians(lat1)) * Math.cos(this.toRadians(lat2)) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  /**
   * Convert degrees to radians
   */
  private static toRadians(degrees: number): number {
    return degrees * (Math.PI / 180);
  }

  /**
   * Calculate speed between two location points
   * @param lat1 - Latitude of first point
   * @param lon1 - Longitude of first point
   * @param timestamp1 - Timestamp of first point (ms)
   * @param lat2 - Latitude of second point
   * @param lon2 - Longitude of second point
   * @param timestamp2 - Timestamp of second point (ms)
   * @returns Speed in m/s
   */
  static calculateSpeed(
    lat1: number, lon1: number, timestamp1: number,
    lat2: number, lon2: number, timestamp2: number
  ): number {
    const distance = this.calculateDistance(lat1, lon1, lat2, lon2);
    const timeDiff = (timestamp2 - timestamp1) / 1000; // Convert to seconds
    return timeDiff > 0 ? distance / timeDiff : 0;
  }

  /**
   * Format coordinates to human-readable string
   * @param latitude - Latitude value
   * @param longitude - Longitude value
   * @param precision - Number of decimal places (default: 6)
   * @returns Formatted coordinate string
   */
  static formatCoordinates(latitude: number, longitude: number, precision: number = 6): string {
    return `${latitude.toFixed(precision)}, ${longitude.toFixed(precision)}`;
  }

  /**
   * Convert speed from m/s to km/h
   * @param speedMps - Speed in meters per second
   * @returns Speed in kilometers per hour
   */
  static mpsToKmh(speedMps: number): number {
    return speedMps * 3.6;
  }

  /**
   * Convert speed from m/s to mph
   * @param speedMps - Speed in meters per second
   * @returns Speed in miles per hour
   */
  static mpsToMph(speedMps: number): number {
    return speedMps * 2.237;
  }

  /**
   * Check if location is within a geofence (circular area)
   * @param lat - Current latitude
   * @param lon - Current longitude
   * @param centerLat - Geofence center latitude
   * @param centerLon - Geofence center longitude
   * @param radius - Geofence radius in meters
   * @returns True if location is within geofence
   */
  static isWithinGeofence(
    lat: number, lon: number,
    centerLat: number, centerLon: number,
    radius: number
  ): boolean {
    const distance = this.calculateDistance(lat, lon, centerLat, centerLon);
    return distance <= radius;
  }

  /**
   * Validate location data
   * @param latitude - Latitude value
   * @param longitude - Longitude value
   * @returns True if coordinates are valid
   */
  static isValidLocation(latitude: number, longitude: number): boolean {
    return latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
  }

  /**
   * Get platform-specific configuration adjustments
   * @param config - Base configuration
   * @returns Adjusted configuration for current platform
   */
  static getPlatformOptimizedConfig(config: LocationTrackingConfig): LocationTrackingConfig {
    const optimizedConfig = { ...config };

    if (Platform.OS === 'ios') {
      // iOS specific optimizations
      if (config.backgroundMode) {
        // iOS requires higher accuracy for background location
        optimizedConfig.accuracy = 'high';
      }
    } else if (Platform.OS === 'android') {
      // Android specific optimizations
      if (config.intervalMs < 5000) {
        // Android battery optimization - removed warning
      }
    }

    return optimizedConfig;
  }
}

/**
 * Location tracking session manager
 */
export class TrackingSession {
  private startTime: number = 0;
  private totalDistance: number = 0;
  private lastLocation: { lat: number; lon: number; timestamp: number } | null = null;
  private locationHistory: Array<{ lat: number; lon: number; timestamp: number }> = [];

  /**
   * Start a new tracking session
   */
  start(): void {
    this.startTime = Date.now();
    this.totalDistance = 0;
    this.lastLocation = null;
    this.locationHistory = [];
  }

  /**
   * Add a location update to the session
   */
  addLocation(latitude: number, longitude: number, timestamp: number): void {
    const currentLocation = { lat: latitude, lon: longitude, timestamp };

    if (this.lastLocation) {
      const distance = LocationUtils.calculateDistance(
        this.lastLocation.lat, this.lastLocation.lon,
        latitude, longitude
      );
      this.totalDistance += distance;
    }

    this.lastLocation = currentLocation;
    this.locationHistory.push(currentLocation);
  }

  /**
   * Get session statistics
   */
  getStats(): {
    duration: number;
    distance: number;
    averageSpeed: number;
    locationCount: number;
  } {
    const duration = Date.now() - this.startTime;
    const averageSpeed = duration > 0 ? (this.totalDistance / (duration / 1000)) : 0;

    return {
      duration,
      distance: this.totalDistance,
      averageSpeed,
      locationCount: this.locationHistory.length
    };
  }

  /**
   * Get location history
   */
  getHistory(): Array<{ lat: number; lon: number; timestamp: number }> {
    return [...this.locationHistory];
  }

  /**
   * Clear session data
   */
  clear(): void {
    this.startTime = 0;
    this.totalDistance = 0;
    this.lastLocation = null;
    this.locationHistory = [];
  }
}
