# RN VietMap Tracking Plugin

[![npm version](https://badge.fury.io/js/rn_vietmap_tracking_plugin.svg)](https://badge.fury.io/js/rn_vietmap_tracking_plugin)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A comprehensive React Native library for GPS location tracking with background support, optimized for the latest React Native versions and built with TypeScript. Perfect for navigation apps, fitness trackers, delivery services, and any application requiring precise location monitoring.

## ✨ Key Features

- 🚀 **Background GPS Tracking** - Continuous location tracking even when app is minimized
- 📱 **Cross-Platform** - Native implementations for both Android and iOS
- ⚡ **TurboModule Architecture** - Built with the new React Native architecture for optimal performance
- 🎯 **High Accuracy** - Configurable precision levels for different use cases
- 🔋 **Battery Optimization** - Smart power management with customizable tracking intervals
- 🛡️ **Permission Handling** - Automatic location permission management
- 📊 **Real-time Updates** - Event-driven location updates with customizable intervals
- 🏃 **Preset Configurations** - Pre-built configurations for Navigation, Fitness, General, and Battery Saver modes
- 📏 **Geofencing** - Built-in distance calculations and geofencing utilities
- 🧪 **TypeScript Support** - Full TypeScript definitions for better development experience

## 📋 Requirements

- React Native >= 0.72.0
- iOS >= 11.0
- Android API Level >= 21 (Android 5.0)
- Google Play Services (Android)
- Core Location Framework (iOS)

## 📦 Installation

```bash
npm install rn_vietmap_tracking_plugin
```

### iOS Setup

Add the following permissions to your `ios/YourProject/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access for tracking functionality.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs background location access for continuous tracking.</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

### Android Setup

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

```typescript
import RnVietmapTrackingPlugin, {
  TrackingPresets,
  LocationData,
  TrackingStatus
} from 'rn_vietmap_tracking_plugin';

// Start tracking with a preset configuration
const startTracking = async () => {
  try {
    // Use pre-configured settings for navigation
    const result = await RnVietmapTrackingPlugin.startLocationTracking(
      TrackingPresets.NAVIGATION
    );
    console.log('Tracking started:', result.success);
  } catch (error) {
    console.error('Failed to start tracking:', error);
  }
};

// Listen for location updates
const locationListener = RnVietmapTrackingPlugin.addLocationListener(
  (location: LocationData) => {
    console.log('New location:', {
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
      speed: location.speed
    });
  }
);

// Stop tracking
const stopTracking = async () => {
  const result = await RnVietmapTrackingPlugin.stopLocationTracking();
  console.log('Tracking stopped:', result.success);

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

### Core Methods

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
