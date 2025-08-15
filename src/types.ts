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
