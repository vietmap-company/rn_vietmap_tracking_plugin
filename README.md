# RN VietMap Tracking Plugin

[![npm version](https://badge.fury.io/js/rn_vietmap_tracking_plugin.svg)](https://badge.fury.io/js/rn_vietmap_tracking_plugin)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A comprehensive React Native library for GPS location tracking with advanced background support, optimized for the latest React Native versions and built with TypeScript. Features the **background_location_2 strategy** with **Force Update Background Mode** for reliable continuous tracking even when the app is minimized.

## ✨ Key Features

- 🚀 **```typescript
// For delivery tracking, navigation - use force mode with fine distance filter
await startTracking(true, 15000, true, 5);   // 15s intervals, always active, 5m filter ignored

// For fitness tracking, general monitoring - use standard mode with medium filter
await startTracking(true, 30000, false, 15); // 30s intervals, 15m distance filtered

// For foreground apps - use standard mode with high precision
await startTracking(false, 5000, false, 5);  // 5s intervals, 5m distance filter

// For battery saver mode - use larger distance filter
await startTracking(true, 60000, false, 100); // 1min intervals, 100m distance filter
```ackground GPS Tracking** - Continuous location tracking with background_location_2 strategy
- 🔥 **Force Update Background Mode** - NEW! Bypasses iOS background limitations for continuous tracking
- 📱 **Cross-Platform** - Native implementations for both Android and iOS
- ⚡ **TurboModule Architecture** - Built with the new React Native architecture for optimal performance
- 🎯 **High Accuracy** - Configurable precision levels for different use cases
- 🔋 **Smart Battery Management** - Dual tracking modes: efficient distance-based vs reliable timer-based
- 🛡️ **Enhanced Permission Handling** - Automatic location permission management with background location support
- 📊 **Real-time Updates** - Event-driven location updates with intelligent throttling
- 🏃 **Preset Configurations** - Pre-built configurations for Navigation, Fitness, General, and Battery Saver modes
- 📏 **Geofencing** - Built-in distance calculations and geofencing utilities
- 🧪 **TypeScript Support** - Full TypeScript definitions for better development experience
- 🌙 **Background Task Management** - Advanced background task chaining for iOS and background services for Android

## 📋 Requirements

- React Native >= 0.72.0
- iOS >= 11.0 (iOS 13+ recommended for enhanced background tasks)
- Android API Level >= 21 (Android 5.0)
- Google Play Services (Android)
- Core Location Framework (iOS)

## 📦 Installation

```bash
npm install rn_vietmap_tracking_plugin
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
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

#### Foreground Service (Optional)

For enhanced background tracking, add the location service to your manifest:

```xml
<application>
    <service
        android:name="com.rnvietmaptrackingplugin.LocationTrackingService"
        android:foregroundServiceType="location"
        android:exported="false" />
</application>
```

## 🚀 Quick Start

### Basic Usage

```typescript
import { startTracking, stopTracking, addLocationUpdateListener } from 'rn_vietmap_tracking_plugin';

// Start basic tracking
const startBasicTracking = async () => {
  try {
    const result = await startTracking(
      false,  // backgroundMode: foreground only
      5000,   // intervalMs: update every 5 seconds
      false,  // forceUpdateBackground: use standard distance-based filtering
      10      // distanceFilter: minimum 10 meters movement required (optional, default: 10)
    );
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
    speed: location.speed
  });
});

// Stop tracking
const stopBasicTracking = async () => {
  try {
    const result = await stopTracking();
    console.log('Tracking stopped:', result);
    locationListener.remove();
  } catch (error) {
    console.error('Failed to stop tracking:', error);
  }
};
```

### Enhanced Background Tracking (background_location_2 Strategy)

```typescript
import { startTracking, stopTracking } from 'rn_vietmap_tracking_plugin';

// Start enhanced background tracking
const startBackgroundTracking = async () => {
  try {
    // Request always location permission first
    await RnVietmapTrackingPlugin.requestAlwaysLocationPermissions();

    // Start continuous background tracking
    const result = await startTracking(
      true,    // backgroundMode: enable background tracking
      5000,    // intervalMs: update every 5 seconds
      false,   // forceUpdateBackground: use distance filter + throttling (default)
      15       // distanceFilter: minimum 15 meters movement required (optional, default: 10)
    );
    console.log('Background tracking started:', result);
  } catch (error) {
    console.error('Failed to start background tracking:', error);
  }
};

// Start FORCED background tracking (bypasses iOS throttling)
const startForcedBackgroundTracking = async () => {
  try {
    await RnVietmapTrackingPlugin.requestAlwaysLocationPermissions();

    // Force continuous updates with timer-based requests
    const result = await startTracking(
      true,    // backgroundMode: enable background tracking
      10000,   // intervalMs: force update every 10 seconds
      true,    // forceUpdateBackground: bypass distance filter and OS throttling
      10       // distanceFilter: ignored in force mode, but can be specified for consistency
    );
    console.log('Forced background tracking started:', result);
  } catch (error) {
    console.error('Failed to start forced tracking:', error);
  }
};

// Start foreground tracking with custom interval
const startForegroundTracking = async () => {
  try {
    const result = await startTracking(
      false,   // backgroundMode: foreground only
      3000,    // intervalMs: update every 3 seconds
      false,   // forceUpdateBackground: not needed for foreground
      5        // distanceFilter: high precision - update every 5 meters
    );
    console.log('Foreground tracking started:', result);
  } catch (error) {
    console.error('Failed to start foreground tracking:', error);
  }
};

// Stop enhanced tracking
const stopEnhancedTracking = async () => {
  try {
    const result = await stopTracking();
    console.log('Enhanced tracking stopped:', result);
  } catch (error) {
    console.error('Failed to stop tracking:', error);
  }
};

  // Clean up listener
  locationListener.remove();
};
```

## 📚 Configuration Options

### Tracking Presets

Choose from pre-configured tracking modes:

```typescript
import { TrackingPresets } from 'rn_vietmap_tracking_plugin';

// High accuracy for turn-by-turn navigation
TrackingPresets.NAVIGATION

// Optimized for fitness and outdoor activities
TrackingPresets.FITNESS

// Balanced accuracy and battery usage
TrackingPresets.GENERAL

// Maximum battery conservation
TrackingPresets.BATTERY_SAVER
```

### Custom Configuration

```typescript
import { LocationTrackingConfig } from 'rn_vietmap_tracking_plugin';

const customConfig: LocationTrackingConfig = {
  enableBackgroundMode: true,
  interval: 5000,              // Update every 5 seconds
  fastestInterval: 2000,       // Fastest possible update
  priority: 'high_accuracy',   // GPS priority
  distanceFilter: 10,          // Minimum distance for updates (meters)
  enableGeofencing: true,
  geofenceRadius: 100,         // Geofence radius (meters)
  foregroundServiceOptions: {
    notificationTitle: 'GPS Tracking Active',
    notificationText: 'Your location is being tracked',
    enableWakeLock: true
  }
};
```

## 🛠️ API Reference

### Enhanced Tracking Methods (Recommended)

#### `startTracking(backgroundMode, intervalMs, forceUpdateBackground?, distanceFilter?)`
Start GPS tracking with enhanced background_location_2 strategy.

```typescript
async function startTracking(
  backgroundMode: boolean,      // Enable background tracking (requires 'Always' permission)
  intervalMs: number = 5000,    // Update interval in milliseconds for throttling
  forceUpdateBackground: boolean = false,  // Force continuous updates bypassing distance filter
  distanceFilter: number = 10   // Minimum distance in meters for location updates
): Promise<string>
```

**Parameters:**
- `backgroundMode`: Enable background tracking (requires "Always" location permission)
- `intervalMs`: Update interval in milliseconds for throttling (default: 5000)
- `forceUpdateBackground`: Force continuous updates bypassing distance filter and OS throttling (default: false)
- `distanceFilter`: Minimum distance in meters for location updates (default: 10, ignored in force mode)

**Examples:**
```typescript
// High precision navigation tracking
await startTracking(true, 1000, false, 5);    // 1s interval, 5m distance filter

// Balanced general tracking
await startTracking(true, 5000, false, 10);   // 5s interval, 10m distance filter

// Battery saver mode
await startTracking(true, 30000, false, 50);  // 30s interval, 50m distance filter

// Force continuous mode (bypasses distance filter)
await startTracking(true, 10000, true, 10);   // 10s forced intervals, distanceFilter ignored
```

#### `stopTracking()`
Stop GPS tracking and cleanup all resources.

```typescript
const result = await stopTracking();
```

### Legacy Configuration Methods

#### `startLocationTracking(config: LocationTrackingConfig)`
Starts GPS location tracking with the specified configuration.

```typescript
const result = await RnVietmapTrackingPlugin.startLocationTracking(config);
```

#### `stopLocationTracking()`
Stops the active location tracking session.

```typescript
const result = await RnVietmapTrackingPlugin.stopLocationTracking();
```

#### `getCurrentLocation(timeout?: number)`
Gets the current device location immediately.

```typescript
const location = await RnVietmapTrackingPlugin.getCurrentLocation(10000);
```

#### `getTrackingStatus()`
Returns the current tracking status and configuration.

```typescript
const status = await RnVietmapTrackingPlugin.getTrackingStatus();
```

### Event Listeners

#### Location Updates
```typescript
const listener = RnVietmapTrackingPlugin.addLocationListener((location) => {
  // Handle location update
});
```

#### Status Changes
```typescript
const statusListener = RnVietmapTrackingPlugin.addStatusListener((status) => {
  // Handle tracking status changes
});
```

### Utility Functions

#### Distance Calculation
```typescript
import { LocationUtils } from 'rn_vietmap_tracking_plugin';

const distance = LocationUtils.calculateDistance(
  { latitude: 21.0285, longitude: 105.8542 }, // Hanoi
  { latitude: 10.8231, longitude: 106.6297 }  // Ho Chi Minh City
);
```

#### Coordinate Formatting
```typescript
const formatted = LocationUtils.formatCoordinates(21.0285, 105.8542, 6);
// Returns: "21.028500, 105.854200"
```

## 🎯 Use Cases

### Navigation Apps
```typescript
// High-accuracy tracking for turn-by-turn navigation
await RnVietmapTrackingPlugin.startLocationTracking(TrackingPresets.NAVIGATION);
```

### Fitness Tracking
```typescript
// Optimized for outdoor activities and sports
await RnVietmapTrackingPlugin.startLocationTracking(TrackingPresets.FITNESS);
```

### Delivery Services
```typescript
// Custom configuration for delivery tracking
const deliveryConfig = {
  ...TrackingPresets.GENERAL,
  interval: 30000, // Update every 30 seconds
  enableGeofencing: true,
  geofenceRadius: 50
};
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

## 📖 Documentation

- [Usage Guide](./USAGE.md) - Detailed usage examples and best practices
- [Development Guide](./GUIDE.md) - Setup and development instructions
- [Changelog](./CHANGELOG.md) - Version history and updates

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on how to get started.

### Development Setup

1. Clone the repository
2. Install dependencies: `npm install`
3. Run the example app: `npm run example ios` or `npm run example android`

## 🏃 How to Run the Example App After Clone

This project uses a monorepo structure. Để chạy app ví dụ (`example`) sau khi clone repo, hãy làm theo các bước sau:

### 1. Cài đặt dependencies ở cả root và example

```bash
# Ở thư mục gốc của repo
npm install

# Di chuyển vào thư mục example
cd example
npm install

# Đảm bảo các package sau được cài riêng trong example:
npm install react react-native @babel/runtime
```

> **Lưu ý:**
> - Nếu bạn dùng `yarn`, thay thế `npm install` bằng `yarn install`.
> - Việc cài riêng `react`, `react-native`, `@babel/runtime` trong `example` là bắt buộc để Metro không bị lỗi module resolution.

### 2. Chạy app ví dụ

```bash
# Trong thư mục example
# iOS
npx react-native run-ios

# Android
npx react-native run-android
```

### 3. Xử lý lỗi Metro hoặc module resolution

Nếu gặp lỗi như `Unable to resolve module react` hoặc `@babel/runtime`, hãy thử:

```bash
# Xóa node_modules và lock file ở cả root và example
rm -rf node_modules example/node_modules package-lock.json example/package-lock.json yarn.lock example/yarn.lock

# Cài lại dependencies
npm install
cd example
npm install
npm install react react-native @babel/runtime
```

### 4. Troubleshooting khác
- Đảm bảo Metro chỉ sử dụng `example/node_modules` (đã cấu hình trong `example/metro.config.js`).
- Nếu vẫn lỗi, thử khởi động lại Metro:
  ```bash
  npx react-native start --reset-cache
  ```
- Đảm bảo bạn đang dùng Node.js >= 16 và npm >= 7.

---
