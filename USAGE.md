# React Native Background Location Tracker

A powerful React Native library for background GPS location tracking with native performance optimization.

## Features

- 🚀 **High Performance**: Native implementation for Android and iOS
- 📍 **Background Tracking**: Continuous location updates even when app is in background
- ⚡ **Configurable**: Customizable update intervals, accuracy, and distance filters
- 🔋 **Battery Optimized**: Smart power management for extended battery life
- 🛡️ **Permission Handling**: Built-in permission management
- 📊 **Real-time Updates**: Event-based location updates with status tracking
- 🔧 **Easy Integration**: Simple API with TypeScript support

## Installation

```bash
npm install rn_vietmap_tracking_plugin
# or
yarn add rn_vietmap_tracking_plugin
```

### iOS Setup

Add the following keys to your `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to track your position</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs location access to track your position in background</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>This app needs location access to track your position in background</string>
```

### Android Setup

Add the following permissions to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

## Usage

### Basic Usage

```typescript
import {
  startLocationTracking,
  stopLocationTracking,
  getCurrentLocation,
  addLocationUpdateListener,
  createDefaultConfig,
  requestLocationPermissions,
  type LocationData
} from 'rn_vietmap_tracking_plugin';

// Request permissions first
const permissionResult = await requestLocationPermissions();
if (permissionResult === 'granted') {
  // Create configuration
  const config = createDefaultConfig(5000); // 5 second intervals

  // Start tracking
  const success = await startLocationTracking(config);
  if (success) {
    console.log('Tracking started successfully');
  }
}
```

### Advanced Configuration

```typescript
import {
  startLocationTracking,
  type LocationTrackingConfig
} from 'rn_vietmap_tracking_plugin';

const config: LocationTrackingConfig = {
  intervalMs: 10000,                    // Update every 10 seconds
  distanceFilter: 50,                   // Update only if moved 50 meters
  accuracy: 'high',                     // 'high', 'medium', or 'low'
  backgroundMode: true,                 // Enable background tracking
  notificationTitle: 'GPS Active',      // Custom notification title (Android)
  notificationMessage: 'Tracking...'    // Custom notification message (Android)
};

await startLocationTracking(config);
```

### Location Updates

```typescript
import { addLocationUpdateListener } from 'rn_vietmap_tracking_plugin';

// Listen for location updates
const subscription = addLocationUpdateListener((location: LocationData) => {
  console.log('New location:', {
    latitude: location.latitude,
    longitude: location.longitude,
    accuracy: location.accuracy,
    timestamp: new Date(location.timestamp)
  });
});

// Don't forget to remove the listener
subscription.remove();
```

### Tracking Status

```typescript
import {
  addTrackingStatusListener,
  getTrackingStatus,
  isTrackingActive
} from 'rn_vietmap_tracking_plugin';

// Check if tracking is active
const isActive = isTrackingActive();

// Get detailed status
const status = await getTrackingStatus();
console.log('Tracking status:', {
  isTracking: status.isTracking,
  duration: status.trackingDuration / 1000, // seconds
  lastUpdate: status.lastLocationUpdate ? new Date(status.lastLocationUpdate) : null
});

// Listen for status changes
const statusSubscription = addTrackingStatusListener((status) => {
  console.log('Status changed:', status);
});
```

### Stop Tracking

```typescript
import { stopLocationTracking } from 'rn_vietmap_tracking_plugin';

const success = await stopLocationTracking();
if (success) {
  console.log('Tracking stopped successfully');
}
```

## API Reference

### Functions

#### `startLocationTracking(config: LocationTrackingConfig): Promise<boolean>`
Start GPS location tracking with the specified configuration.

#### `stopLocationTracking(): Promise<boolean>`
Stop GPS location tracking.

#### `getCurrentLocation(): Promise<LocationData>`
Get the current location immediately.

#### `isTrackingActive(): boolean`
Check if location tracking is currently active.

#### `getTrackingStatus(): Promise<TrackingStatus>`
Get detailed tracking status information.

#### `updateTrackingConfig(config: LocationTrackingConfig): Promise<boolean>`
Update tracking configuration while tracking is active.

#### `requestLocationPermissions(): Promise<string>`
Request location permissions from the user.

#### `hasLocationPermissions(): Promise<boolean>`
Check if location permissions are granted.

#### `addLocationUpdateListener(callback: LocationUpdateCallback): Subscription`
Subscribe to location updates.

#### `addTrackingStatusListener(callback: TrackingStatusCallback): Subscription`
Subscribe to tracking status changes.

#### `createDefaultConfig(intervalMs?: number): LocationTrackingConfig`
Create a default configuration with optional custom interval.

### Types

#### `LocationTrackingConfig`
```typescript
interface LocationTrackingConfig {
  intervalMs: number;                    // Update interval in milliseconds
  distanceFilter: number;                // Minimum distance in meters
  accuracy: 'high' | 'medium' | 'low';   // Desired accuracy
  backgroundMode: boolean;               // Background tracking enabled
  notificationTitle?: string;            // Android notification title
  notificationMessage?: string;          // Android notification message
}
```

#### `LocationData`
```typescript
interface LocationData {
  latitude: number;      // Latitude in degrees
  longitude: number;     // Longitude in degrees
  altitude: number;      // Altitude in meters
  accuracy: number;      // Accuracy in meters
  speed: number;         // Speed in m/s
  bearing: number;       // Bearing in degrees
  timestamp: number;     // Timestamp in milliseconds
}
```

#### `TrackingStatus`
```typescript
interface TrackingStatus {
  isTracking: boolean;           // Whether tracking is active
  lastLocationUpdate?: number;   // Last update timestamp
  trackingDuration: number;      // Duration in milliseconds
}
```

## Best Practices

1. **Request Permissions Early**: Always request location permissions before starting tracking.

2. **Configure Appropriately**: Choose appropriate intervals and accuracy based on your use case:
   - For navigation: `intervalMs: 1000`, `accuracy: 'high'`
   - For fitness tracking: `intervalMs: 5000`, `accuracy: 'high'`
   - For general tracking: `intervalMs: 30000`, `accuracy: 'medium'`

3. **Handle Permissions**: Always check permission status and handle denied permissions gracefully.

4. **Battery Optimization**: Use appropriate distance filters to reduce unnecessary updates.

5. **Clean Up**: Remove event listeners when components unmount to prevent memory leaks.

## Example App

The package includes a complete example app demonstrating all features. To run it:

```bash
cd example
npm install
# iOS
npx react-native run-ios
# Android
npx react-native run-android
```

## Troubleshooting

### iOS Issues

- **Background location not working**: Make sure you have `NSLocationAlwaysAndWhenInUseUsageDescription` in Info.plist
- **Permission denied**: Check that location permissions are properly requested and granted

### Android Issues

- **Background location not working**: Ensure `ACCESS_BACKGROUND_LOCATION` permission is granted
- **App killed in background**: The foreground service should keep the app alive, but some devices may still kill it

## License

MIT

## Contributing

Contributions are welcome! Please read the contributing guidelines before submitting PRs.
