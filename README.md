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
    <string>com.yourapp.background-location</string>
    <string>com.yourapp.location-sync</string>
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

## 📄 License

MIT License - see the [LICENSE](LICENSE) file for details.

## 🔧 Troubleshooting

### Common Issues

**Android: Location updates not working in background**
- Ensure all required permissions are added to AndroidManifest.xml
- Check that battery optimization is disabled for your app
- Verify Google Play Services is installed and updated

**iOS: Background location not working**
- Add NSLocationAlwaysAndWhenInUseUsageDescription to Info.plist
- Include "location" in UIBackgroundModes
- Request "always" location permission

**TypeScript errors**
- Ensure you're using TypeScript 4.5 or higher
- Check that all peer dependencies are installed

### Getting Help

- 📚 Check the [Usage Guide](./USAGE.md) for detailed examples
- 🐛 Report bugs in [GitHub Issues](https://github.com/yourusername/rn_vietmap_tracking_plugin/issues)
- 💬 Ask questions in [Discussions](https://github.com/yourusername/rn_vietmap_tracking_plugin/discussions)

---

**Made with ❤️ using [create-react-native-library](https://github.com/callstack/react-native-builder-bob)**

## 🌙 Background Tracking Details

### Background Location Strategy

This plugin implements the **background_location_2 strategy** for reliable background GPS tracking:

#### iOS Implementation:
- **Continuous Location Updates**: Uses `startUpdatingLocation()` instead of timer-based requests
- **Background Task Chaining**: Automatically renews background tasks before 30-second expiration
- **Deferred Location Updates**: Optimizes battery usage when location changes are minimal
- **Significant Location Changes**: Fallback monitoring for major location changes
- **iOS 13+ Background Tasks**: Enhanced background processing with `BGTaskScheduler`

#### Android Implementation:
- **Continuous Location Updates**: Uses `FusedLocationProviderClient` with continuous requests
- **Foreground Service**: Optional foreground service for long-running background tracking
- **Battery Optimization**: Intelligent throttling based on `intervalMs` parameter
- **Background Location Permission**: Handles Android 10+ background location restrictions

### Dual Tracking Mechanism: Timer + Distance

The plugin uses **two complementary filters** to optimize both accuracy and battery life:

#### 1. **Distance Filter** (Native iOS/Android)
- Controls **when** location updates are triggered based on movement
- iOS: `locationManager.distanceFilter` - only calls `didUpdateLocations` when user moves ≥ threshold
- Android: `LocationRequest.setSmallestDisplacement()` - similar behavior
- **Configurable via `distanceFilter` parameter** (default: 10 meters)

#### 2. **Timer Throttling** (JavaScript controlled)
- Controls **frequency** of updates sent to React Native
- Configured via `intervalMs` parameter in `startTracking(backgroundMode, intervalMs, forceUpdateBackground, distanceFilter)`
- Applied in native code after receiving location from distance filter

#### **Example Scenario:**
```javascript
// Configuration with custom distance filter
await startTracking(true, 30000, false, 15); // 30-second timer + 15m distance filter

// Timeline of user movement:
// 10:00:00 - User moves 20m → iOS calls didUpdateLocations → Timer OK (first update) → ✅ Send update
// 10:00:15 - User moves 12m → iOS doesn't call (< 15m distance) → ❌ No update
// 10:00:30 - User moves 18m → iOS calls didUpdateLocations → Timer OK (>30s passed) → ✅ Send update
// 10:00:45 - User moves 8m  → iOS doesn't call (< 15m distance) → ❌ No update
```

#### **Benefits of Dual Mechanism:**
- **Distance Filter**: Prevents updates when user is stationary or moving short distances (saves battery)
- **Timer Throttling**: Prevents excessive updates when user moves frequently (saves battery + bandwidth)
- **Combined Effect**: Only sends meaningful location updates at controlled intervals
- **Customizable Precision**: Adjust `distanceFilter` based on use case (5m for navigation, 50m for battery saver)

#### **Configuration Examples:**
```javascript
// Navigation - frequent updates with high precision
await startTracking(false, 1000, false, 5);  // 1s timer + 5m distance

// General tracking - balanced performance
await startTracking(true, 30000, false, 10);  // 30s timer + 10m distance

// Battery saver - minimal updates with large distance threshold
await startTracking(true, 300000, false, 50); // 5min timer + 50m distance

// Force mode - bypasses distance filter completely
await startTracking(true, 15000, true, 10);   // 15s timer, distanceFilter ignored
```

### Distance Filter Configuration Guide

Choose the right `distanceFilter` value based on your use case:

| Use Case | Recommended `distanceFilter` | Reasoning |
|----------|------------------------------|-----------|
| **Turn-by-turn Navigation** | 5-10 meters | High precision for accurate route guidance |
| **Fitness Tracking** | 10-15 meters | Balance between accuracy and battery life |
| **General Monitoring** | 15-25 meters | Reasonable updates without excessive battery drain |
| **Battery Saver Mode** | 50-100 meters | Minimal updates, maximum battery conservation |
| **Delivery/Fleet Tracking** | 20-30 meters | Track significant movement, reduce noise |

### Dual Tracking Mechanism Example

Here's a practical scenario showing how distance filter (15m) and timer throttling (30s interval) work together:

```
Configuration: distanceFilter = 15m, intervalMs = 30000 (30 seconds)

Timeline:
- 10:00:00 - User moves 20m → Timer OK → ✅ Send update
- 10:00:15 - User moves 12m → Distance < 15m → ❌ No update
- 10:00:30 - User moves 18m → Timer OK → ✅ Send update
- 10:00:45 - User moves 8m  → Distance < 15m → ❌ No update
```

**How it Works:**
1. **Distance Filter (Native)**: iOS/Android only triggers location callbacks when movement ≥ 15m
2. **Timer Throttling (Plugin)**: Our plugin only sends updates if ≥ 30s have passed since last update
3. **Result**: Battery-efficient tracking that captures meaningful movement while avoiding excessive updates

### Key Advantages:

1. **No 30-Second Limitation**: Unlike timer-based approaches, continuous updates persist beyond background task limits
2. **Battery Efficient**: Dual filtering (distance + timer) minimizes unnecessary updates and power consumption
3. **Reliable Background Tracking**: Background task chaining ensures uninterrupted location services
4. **Cross-Platform Consistency**: Similar behavior across iOS and Android platforms
5. **Intelligent Filtering**: Only processes location updates when user actually moves meaningful distances
6. **Configurable Precision**: Customizable `distanceFilter` allows fine-tuning for different use cases

### Distance Filter Best Practices:

#### **Dynamic Distance Filtering**
```typescript
// Adjust distance filter based on user activity
const getOptimalDistanceFilter = (userActivity: string, speed: number) => {
  switch (userActivity) {
    case 'walking':
      return speed > 1.5 ? 5 : 10;  // 5m for fast walking, 10m for slow
    case 'driving':
      return speed > 15 ? 20 : 10;  // 20m for highway, 10m for city driving
    case 'stationary':
      return 50;                    // Large filter when not moving
    default:
      return 15;                    // Balanced default
  }
};

// Example usage
const distanceFilter = getOptimalDistanceFilter(detectedActivity, currentSpeed);
await startTracking(true, 10000, false, distanceFilter);
```

#### **Common Pitfalls to Avoid**
- ❌ **Too Small Filter (≤2m)**: May trigger on GPS noise, excessive battery drain
- ❌ **Too Large Filter (≥200m)**: Miss important location changes, poor user experience
- ❌ **Fixed Filter**: Not adapting to different scenarios reduces efficiency
- ✅ **Adaptive Filter**: Adjust based on speed, activity, and app state

#### **Optimal Settings by Scenario**
```typescript
// Indoor/Office tracking - larger filter to avoid GPS drift
await startTracking(true, 60000, false, 25);

// Outdoor fitness - medium filter for good tracking without noise
await startTracking(true, 10000, false, 12);

// Vehicle navigation - small filter for turn-by-turn accuracy
await startTracking(false, 2000, false, 6);

// Background monitoring - large filter for battery conservation
await startTracking(true, 120000, false, 75);
```

### Permission Requirements:

#### iOS:
- `NSLocationWhenInUseUsageDescription`: For foreground tracking
- `NSLocationAlwaysAndWhenInUseUsageDescription`: For background tracking
- `UIBackgroundModes`: Include `location`, `background-processing`, `background-fetch`

#### Android:
- `ACCESS_FINE_LOCATION`: For precise location access
- `ACCESS_BACKGROUND_LOCATION`: Required for background tracking (Android 10+)
- `FOREGROUND_SERVICE_LOCATION`: For foreground service implementation

### Force Update Background Mode

**When to use `forceUpdateBackground: true`:**

```typescript
// Problem: iOS background location becomes unreliable after 10-30 minutes
await startTracking(true, 30000, false, 10); // May stop working in background after 30min

// Solution: Force continuous updates bypassing iOS system throttling
await startTracking(true, 10000, true, 10);  // Continuous updates regardless of OS limits
//                   ↑     ↑      ↑     ↑
//               background 10s   force  distanceFilter ignored in force mode
```

#### **Comparison of Tracking Modes:**

| Mode | `forceUpdateBackground` | `distanceFilter` | Behavior | Reliability | Battery Impact |
|------|------------------------|------------------|----------|-------------|----------------|
| **Standard Background** | `false` | ✅ Applied (e.g., 10m) | Distance filter + timer throttling | Good for 10-30 min, then sporadic | Low |
| **Forced Background** | `true` | ❌ Ignored | Timer-based requests, no distance filter | Continuous, bypasses iOS throttling | Higher |
| **Foreground** | `false` | ✅ Applied (e.g., 5m) | Continuous updates with distance filtering | Excellent | Low-Medium |

#### **How Force Update Works:**

1. **Standard Mode (`forceUpdateBackground: false`):**
   ```
   iOS CLLocationManager.startUpdatingLocation() + distanceFilter
   → Distance filter triggers (≥10m movement) → Plugin throttles → Send to React Native
   → Subject to iOS background limitations after 30min
   ```

2. **Force Mode (`forceUpdateBackground: true`):**
   ```
   Timer.scheduleAtFixedRate(intervalMs) + No distance filter
   → Request location directly → Always send → React Native
   → Bypasses iOS distance filter and system throttling completely
   ```

#### **Trade-offs:**

**Advantages of Force Mode:**
- ✅ Continuous updates even after 30+ minutes in background
- ✅ Predictable timing intervals
- ✅ Not affected by iOS system location throttling
- ✅ Works during low movement periods

**Disadvantages of Force Mode:**
- ❌ Higher battery consumption
- ❌ May receive same location multiple times when stationary
- ❌ Less efficient than distance-based filtering
- ❌ Requires careful interval tuning

#### **Recommended Usage:**

```typescript
// For delivery tracking, navigation - use force mode
await startTracking(true, 15000, true);  // 15s intervals, always active

// For fitness tracking, general monitoring - use standard mode
await startTracking(true, 30000, false); // 30s intervals, distance filtered

// For foreground apps - use standard mode
await startTracking(false, 5000, false); // 5s intervals, high accuracy
```
