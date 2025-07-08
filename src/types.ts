export interface LocationTrackingConfig {
  /** Interval between location updates in milliseconds */
  intervalMs: number;
  /** Minimum distance between location updates in meters */
  distanceFilter: number;
  /** Desired accuracy in meters */
  accuracy: 'high' | 'medium' | 'low';
  /** Whether to continue tracking in background */
  backgroundMode: boolean;
  /** Custom notification title for foreground service (Android) */
  notificationTitle?: string;
  /** Custom notification message for foreground service (Android) */
  notificationMessage?: string;
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
export type LocationErrorCallback = (error: { error: string; code: string; timestamp: number }) => void;
export type PermissionChangeCallback = (permission: { status: string; timestamp: number }) => void;
