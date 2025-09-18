# @vietmap/rn_vietmap_tracking_plugin

[![npm version](https://badge.fury.io/js/@vietmap/rn_vietmap_tracking_plugin.svg)](https://badge.fury.io/js/@vietmap/rn_vietmap_tracking_plugin)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A comprehensive React Native library for GPS location tracking with VietmapTrackingSDK integration, featuring advanced background support, speed alerts, and route monitoring. Built with TypeScript and optimized for the latest React Native versions.

## ✨ Key Features

- 🚀 **Background GPS Tracking** - Continuous location tracking with VietmapTrackingSDK integration
- 🗺️ **VietmapTrackingSDK Integration** - Native SDK integration for enhanced tracking capabilities
- 🚨 **Speed Alert System** - Real-time speed monitoring with native speech synthesis
- 📱 **Cross-Platform** - Native implementations for both Android and iOS
- ⚡ **TurboModule Architecture** - Built with the new React Native architecture for optimal performance
- 🎯 **High Accuracy** - Configurable precision levels for different use cases
- 🔋 **Smart Battery Management** - Optimized tracking configurations for battery efficiency
- 🛡️ **Enhanced Permission Handling** - Automatic location permission management with background location support
- 📊 **Real-time Updates** - Event-driven location updates with intelligent throttling
- 🏃 **Tracking Presets** - Pre-built utility configurations for Navigation, Fitness, General, and Battery Saver modes
- 📏 **Location Utilities** - Built-in distance calculations, speed conversions, and coordinate formatting
- 🧪 **TypeScript Support** - Full TypeScript definitions for better development experience
- � **Session Management** - Built-in tracking session statistics and history management

## 📋 Requirements

- React Native >= 0.72.0
- iOS >= 11.0 (iOS 13+ recommended for enhanced background tasks)
- Android API Level >= 21 (Android 5.0)
- Google Play Services (Android)
- Core Location Framework (iOS)

## 📦 Installation

```bash
npm install @vietmap/rn_vietmap_tracking_plugin
```

### iOS Setup

#### Basic Configuration

Add the following permissions to your `ios/YourProject/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to track your GPS location when using the app.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs continuous location access to track your GPS location even when the app is in the background. This enables features like route tracking, delivery monitoring, and location-based services that work seamlessly while you use other apps.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>This app needs background location access to provide continuous GPS tracking when the app is not actively in use. This is essential for tracking routes, monitoring location changes, and maintaining location services while the app runs in the background.</string>
```

#### Background Modes Configuration

Add background capabilities for enhanced tracking:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>background-processing</string>
    <string>background-fetch</string>
</array>
```

#### Background Task Identifiers (iOS 13+)

For advanced background processing capabilities:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.vietmaptrackingsdk.location-sync</string>
</array>
```

### Android Setup

#### Permissions

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

## 🚀 Quick Start

### Initial Configuration

Before using any tracking features, configure the VietmapTrackingSDK:

```typescript
import { configure, configureAlertAPI } from '@vietmap/rn_vietmap_tracking_plugin';

// Configure VietmapTrackingSDK with your API key
await configure('YOUR_VIETMAP_API_KEY');

// Optional: Configure Alert API for speed monitoring
await configureAlertAPI('YOUR_ALERT_API_URL', 'YOUR_ALERT_API_KEY');
```

### Basic Location Tracking

```typescript
import {
  startTracking,
  stopTracking,
  addLocationUpdateListener,
  addTrackingStatusListener
} from '@vietmap/rn_vietmap_tracking_plugin';

// Start tracking with custom configuration
const startLocationTracking = async () => {
  try {
    const config = {
      intervalMs: 5000,           // Update every 5 seconds
      distanceFilter: 10,         // Minimum 10 meters movement
      accuracy: 'high',           // High accuracy GPS
      backgroundMode: true,       // Enable background tracking
      notificationTitle: 'GPS Tracking Active',
      notificationMessage: 'Your location is being tracked'
    };

    const result = await startTracking(config);
    console.log('Tracking started:', result);
  } catch (error) {
    console.error('Failed to start tracking:', error);
  }
};

// Listen for location updates
const locationListener = addLocationUpdateListener((location) => {
  console.log('New location:', {
    latitude: location.latitude,
    longitude: location.longitude,
    accuracy: location.accuracy,
    speed: location.speed,
    timestamp: location.timestamp
  });
});

// Listen for tracking status changes
const statusListener = addTrackingStatusListener((status) => {
  console.log('Tracking status:', status.isTracking);
});

// Stop tracking
const stopLocationTracking = async () => {
  try {
    const result = await stopTracking();
    console.log('Tracking stopped:', result);

    // Clean up listeners
    locationListener.remove();
    statusListener.remove();
  } catch (error) {
    console.error('Failed to stop tracking:', error);
  }
};
```

### Speed Alert System

```typescript
import { turnOnAlert, turnOffAlert } from '@vietmap/rn_vietmap_tracking_plugin';

// Enable speed monitoring with native speech alerts
const enableSpeedAlerts = async () => {
  try {
    const success = await turnOnAlert();
    if (success) {
      console.log('Speed alerts enabled');
      // Speed violations will be announced using native speech synthesis
    }
  } catch (error) {
    console.error('Failed to enable speed alerts:', error);
  }
};

// Disable speed monitoring
const disableSpeedAlerts = async () => {
  try {
    const success = await turnOffAlert();
    if (success) {
      console.log('Speed alerts disabled');
    }
  } catch (error) {
    console.error('Failed to disable speed alerts:', error);
  }
};
```
## 📚 Configuration Options

### LocationTrackingConfig Interface

```typescript
interface LocationTrackingConfig {
  /** Interval between location updates in milliseconds */
  intervalMs: number;
  /** Minimum distance between location updates in meters */
  distanceFilter: number;
  /** Desired accuracy level */
  accuracy: 'high' | 'medium' | 'low';
  /** Whether to continue tracking in background */
  backgroundMode: boolean;
  /** Custom notification title for foreground service (Android) */
  notificationTitle?: string;
  /** Custom notification message for foreground service (Android) */
  notificationMessage?: string;
}
```

### Tracking Presets (Utilities)

Pre-configured tracking modes available as utilities:

```typescript
import { TrackingPresets } from '@vietmap/rn_vietmap_tracking_plugin';

// High accuracy for turn-by-turn navigation (1 second updates)
TrackingPresets.NAVIGATION

// Optimized for fitness and outdoor activities (5 second updates)
TrackingPresets.FITNESS

// Balanced accuracy and battery usage (30 second updates)
TrackingPresets.GENERAL

// Maximum battery conservation (5 minute updates)
TrackingPresets.BATTERY_SAVER
```

### Custom Configuration Examples

```typescript
// High precision navigation tracking
const navigationConfig = {
  intervalMs: 1000,              // Update every second
  distanceFilter: 5,             // High precision - 5 meter filter
  accuracy: 'high',              // GPS high accuracy
  backgroundMode: true,          // Continue in background
  notificationTitle: 'Navigation Active',
  notificationMessage: 'Tracking your route'
};

// Battery optimized tracking
const batteryConfig = {
  intervalMs: 60000,             // Update every minute
  distanceFilter: 100,           // 100 meter filter for battery savings
  accuracy: 'medium',            // Balanced accuracy
  backgroundMode: true,
  notificationTitle: 'Background Tracking',
  notificationMessage: 'Tracking with battery optimization'
};

// Fitness tracking
const fitnessConfig = {
  intervalMs: 5000,              // Update every 5 seconds
  distanceFilter: 10,            // 10 meter precision
  accuracy: 'high',              // High accuracy for sports
  backgroundMode: true,
  notificationTitle: 'Fitness Tracking',
  notificationMessage: 'Recording your workout'
};
```

## 🛠️ API Reference

### Core Configuration Methods

#### `configure(apiKey: string, baseURL?: string)`
Configure VietmapTrackingSDK with API key and optional base URL.

```typescript
await configure('YOUR_VIETMAP_API_KEY');
// or with custom base URL
await configure('YOUR_VIETMAP_API_KEY', 'https://custom-api.vietmap.vn');
```

#### `configureAlertAPI(url: string, apiKey: string)`
Configure Alert API for speed monitoring features.

```typescript
await configureAlertAPI('YOUR_ALERT_API_URL', 'YOUR_ALERT_API_KEY');
```

### Tracking Control Methods

#### `startTracking(config: LocationTrackingConfig)`
Start GPS tracking with specified configuration.

```typescript
const config = {
  intervalMs: 5000,
  distanceFilter: 10,
  accuracy: 'high',
  backgroundMode: true,
  notificationTitle: 'GPS Tracking',
  notificationMessage: 'Your location is being tracked'
};

const result = await startTracking(config);
```

#### `stopTracking()`
Stop GPS tracking and cleanup all resources.

```typescript
const result = await stopTracking();
```

#### `getCurrentLocation()`
Get the current device location immediately.

```typescript
const location = await getCurrentLocation();
console.log(location.latitude, location.longitude);
```

#### `getTrackingStatus()`
Get detailed tracking status and configuration.

```typescript
const status = await getTrackingStatus();
console.log('Is tracking:', status.isTracking);
```

#### `updateTrackingConfig(config: LocationTrackingConfig)`
Update tracking configuration while tracking is active.

```typescript
const newConfig = { ...currentConfig, intervalMs: 10000 };
const success = await updateTrackingConfig(newConfig);
```

### Permission Management

#### `requestLocationPermissions()`
Request basic location permissions.

```typescript
const result = await requestLocationPermissions();
console.log('Granted:', result.granted);
```

#### `hasLocationPermissions()`
Check current location permission status.

```typescript
const result = await hasLocationPermissions();
console.log('Status:', result.status); // 'granted' | 'denied' | 'not_granted'
```

#### `requestAlwaysLocationPermissions()`
Request always location permissions (required for background tracking).

```typescript
const status = await requestAlwaysLocationPermissions();
```

### Event Listeners

#### `addLocationUpdateListener(callback)`
Subscribe to location updates.

```typescript
const listener = addLocationUpdateListener((location) => {
  console.log('New location:', location);
});

// Remove listener when done
listener.remove();
```

#### `addTrackingStatusListener(callback)`
Subscribe to tracking status changes.

```typescript
const statusListener = addTrackingStatusListener((status) => {
  console.log('Tracking status changed:', status.isTracking);
});

// Remove listener when done
statusListener.remove();
```

### Speed Alert Methods

#### `turnOnAlert()`
Enable speed monitoring with native speech synthesis.

```typescript
const success = await turnOnAlert();
```

#### `turnOffAlert()`
Disable speed monitoring.

```typescript
const success = await turnOffAlert();
```

### Utility Functions

#### Distance Calculation
```typescript
import { LocationUtils } from '@vietmap/rn_vietmap_tracking_plugin';

const distance = LocationUtils.calculateDistance(
  21.0285, 105.8542, // Hanoi coordinates
  10.8231, 106.6297  // Ho Chi Minh City coordinates
);
console.log(`Distance: ${distance} meters`);
```

#### Coordinate Formatting
```typescript
const formatted = LocationUtils.formatCoordinates(21.0285, 105.8542, 6);
// Returns: "21.028500, 105.854200"
```

#### Speed Conversion
```typescript
const kmh = LocationUtils.mpsToKmh(speedInMps);
const mph = LocationUtils.mpsToMph(speedInMps);
```

#### Session Management
```typescript
import { TrackingSession } from '@vietmap/rn_vietmap_tracking_plugin';

const session = new TrackingSession();
session.start();

// Add locations as they come in
session.addLocation(lat, lon, timestamp);

// Get session statistics
const stats = session.getStats();
console.log('Duration:', stats.duration);
console.log('Distance:', stats.distance);
console.log('Average speed:', stats.averageSpeed);
```
## 🎯 Use Cases & Examples

### Navigation Apps
```typescript
import { startTracking, TrackingPresets } from '@vietmap/rn_vietmap_tracking_plugin';

// High-accuracy tracking for turn-by-turn navigation
await startTracking(TrackingPresets.NAVIGATION);

// Or custom high-precision config
const navigationConfig = {
  intervalMs: 1000,           // 1 second updates
  distanceFilter: 5,          // 5 meter precision
  accuracy: 'high',
  backgroundMode: true,
  notificationTitle: 'Navigation Active',
  notificationMessage: 'Tracking your route'
};
await startTracking(navigationConfig);
```

### Fitness Tracking
```typescript
// Optimized for outdoor activities and sports
await startTracking(TrackingPresets.FITNESS);

// With custom session management
import { TrackingSession } from '@vietmap/rn_vietmap_tracking_plugin';

const session = new TrackingSession();
session.start();

const locationListener = addLocationUpdateListener((location) => {
  session.addLocation(location.latitude, location.longitude, location.timestamp);

  const stats = session.getStats();
  console.log(`Distance: ${(stats.distance / 1000).toFixed(2)} km`);
  console.log(`Speed: ${LocationUtils.mpsToKmh(stats.averageSpeed).toFixed(1)} km/h`);
});
```

### Delivery Services
```typescript
// Custom configuration for delivery tracking
const deliveryConfig = {
  intervalMs: 30000,          // Update every 30 seconds
  distanceFilter: 50,         // 50 meter filter
  accuracy: 'high',
  backgroundMode: true,
  notificationTitle: 'Delivery Tracking',
  notificationMessage: 'Tracking delivery route'
};

await startTracking(deliveryConfig);

// Monitor delivery progress
const statusListener = addTrackingStatusListener((status) => {
  if (status.isTracking) {
    updateDeliveryStatus('In Transit');
  }
});
```

### Fleet Management
```typescript
// Battery optimized for long-term fleet tracking
await startTracking(TrackingPresets.BATTERY_SAVER);

// With geofencing capabilities
import { LocationUtils } from '@vietmap/rn_vietmap_tracking_plugin';

const depotLat = 21.0285;
const depotLon = 105.8542;
const geofenceRadius = 100; // 100 meters

const locationListener = addLocationUpdateListener((location) => {
  const isInDepot = LocationUtils.isWithinGeofence(
    location.latitude, location.longitude,
    depotLat, depotLon, geofenceRadius
  );

  if (isInDepot) {
    console.log('Vehicle returned to depot');
  }
});
```

## 🧪 Testing

Run the test suite:

```bash
npm test
```

Test the package locally:

```bash
npm run test:local
```

Run the example app:

```bash
# Navigate to example directory
cd example

# Install dependencies
npm install

# iOS
npx react-native run-ios

# Android
npx react-native run-android
```

## 📖 Documentation

- [Usage Guide](./USAGE.md) - Detailed usage examples and best practices
- [Android Integration Guide](./ANDROID_INTEGRATION_GUIDE.md) - Android-specific setup instructions
- [Changelog](./CHANGELOG.md) - Version history and updates

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on how to get started.

### Development Setup

1. Clone the repository
2. Install dependencies: `npm install`
3. Navigate to example: `cd example && npm install`
4. Run the example app: `npx react-native run-ios` or `npx react-native run-android`

## 🏃 How to Run the Example App After Clone

This project uses a monorepo structure. To run the example app after cloning:

### 1. Install dependencies at both root and example levels

```bash
# At the root of the repo
npm install

# Navigate to example directory
cd example
npm install

# Ensure React Native dependencies are installed in example
npm install react react-native @babel/runtime
```

> **Note:**
> - If using `yarn`, replace `npm install` with `yarn install`
> - Installing `react`, `react-native`, `@babel/runtime` separately in `example` is required to prevent Metro module resolution errors

### 2. Run the example app

```bash
# In the example directory
# iOS
npx react-native run-ios

# Android
npx react-native run-android
```

### 3. Troubleshooting Metro or module resolution issues

If you encounter errors like `Unable to resolve module react` or `@babel/runtime`:

```bash
# Remove node_modules and lock files from both root and example
rm -rf node_modules example/node_modules package-lock.json example/package-lock.json yarn.lock example/yarn.lock

# Reinstall dependencies
npm install
cd example
npm install
npm install react react-native @babel/runtime
```

### 4. Additional troubleshooting
- Ensure Metro only uses `example/node_modules` (configured in `example/metro.config.js`)
- If issues persist, restart Metro with cache reset:
  ```bash
  npx react-native start --reset-cache
  ```
- Ensure you're using Node.js >= 16 and npm >= 7

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- VietmapTrackingSDK for providing the core location tracking capabilities
- React Native community for the excellent framework and tools
- Contributors who help improve this library

## 📞 Support

For issues and questions:
- Create an issue on [GitHub](https://github.com/vietmap-company/rn_vietmap_tracking_plugin)
- Check existing [documentation](./USAGE.md)
- Review [Android Integration Guide](./ANDROID_INTEGRATION_GUIDE.md) for platform-specific help
