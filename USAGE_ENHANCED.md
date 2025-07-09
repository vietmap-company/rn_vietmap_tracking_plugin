# 🚀 RN VietMap Tracking Plugin - Usage Guide

## Overview

This guide provides comprehensive documentation for the RN VietMap Tracking Plugin, featuring the advanced **background_location_2 strategy** for reliable GPS tracking both in foreground and background modes.

## 📱 Platform Support

- **iOS**: 11.0+ (iOS 13+ recommended for enhanced background tasks)
- **Android**: API Level 21+ (Android 5.0+)
- **React Native**: 0.72.0+

## 🌟 Key Features

### Enhanced Background Tracking Strategy

The plugin implements the **background_location_2 strategy** which provides:

- **Continuous Location Updates**: Uses native location services instead of timer-based requests
- **Background Task Chaining**: Automatically renews background tasks to maintain tracking beyond 30 seconds
- **Battery Optimization**: Intelligent throttling and deferred updates to minimize power consumption
- **Cross-Platform Reliability**: Consistent behavior across iOS and Android

## 🚀 Quick Start

### Basic Import

```typescript
import RnVietmapTrackingPlugin, {
  startTracking,
  stopTracking,
  addLocationUpdateListener,
  requestAlwaysLocationPermissions,
  type LocationData
} from 'rn_vietmap_tracking_plugin';
```

### Enhanced Background Tracking

```typescript
// Request permissions for background tracking
const requestBackgroundPermissions = async () => {
  try {
    const result = await requestAlwaysLocationPermissions();
    if (result === 'granted') {
      console.log('✅ Background permissions granted');
      return true;
    } else {
      console.log('❌ Background permissions denied:', result);
      return false;
    }
  } catch (error) {
    console.error('Permission error:', error);
    return false;
  }
};

// Start background tracking with continuous updates
const startBackgroundTracking = async () => {
  const hasPermission = await requestBackgroundPermissions();
  if (!hasPermission) return;

  try {
    const result = await startTracking(
      true,    // backgroundMode: enable background tracking
      5000     // intervalMs: throttle updates to 5 seconds
    );
    console.log('Background tracking started:', result);
  } catch (error) {
    console.error('Failed to start background tracking:', error);
  }
};

// Start foreground tracking
const startForegroundTracking = async () => {
  try {
    const result = await startTracking(
      false,   // backgroundMode: foreground only
      3000     // intervalMs: update every 3 seconds
    );
    console.log('Foreground tracking started:', result);
  } catch (error) {
    console.error('Failed to start foreground tracking:', error);
  }
};

// Stop tracking
const stopEnhancedTracking = async () => {
  try {
    const result = await stopTracking();
    console.log('Tracking stopped:', result);
  } catch (error) {
    console.error('Failed to stop tracking:', error);
  }
};
```

### Location Updates Listener

```typescript
import { addLocationUpdateListener } from 'rn_vietmap_tracking_plugin';

// Set up location listener
const locationSubscription = addLocationUpdateListener((location: LocationData) => {
  console.log('📍 New location:', {
    latitude: location.latitude,
    longitude: location.longitude,
    accuracy: location.accuracy,
    speed: location.speed,
    timestamp: location.timestamp
  });

  // Process location data
  updateUserLocation(location);
});

// Clean up subscription
const cleanup = () => {
  if (locationSubscription) {
    locationSubscription.remove();
  }
};
```

## 🔧 Configuration Options

### Enhanced Tracking Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `backgroundMode` | `boolean` | Enable background tracking | `false` |
| `intervalMs` | `number` | Update throttling interval (ms) | `5000` |

### Tracking Intervals

- **High Frequency**: 1000-3000ms (for navigation/fitness)
- **Standard**: 5000ms (for general tracking)
- **Battery Saver**: 10000-30000ms (for minimal updates)

```typescript
// High frequency for navigation
await startTracking(true, 1000);

// Standard frequency for general tracking
await startTracking(true, 5000);

// Battery saver mode
await startTracking(true, 30000);
```

## 📍 Location Data Structure

```typescript
interface LocationData {
  latitude: number;        // GPS latitude
  longitude: number;       // GPS longitude
  altitude: number;        // Altitude in meters
  accuracy: number;        // Horizontal accuracy in meters
  speed: number;          // Speed in meters per second
  bearing: number;        // Direction of movement (0-360°)
  timestamp: number;      // Unix timestamp in milliseconds
}
```

## 🛡️ Permission Management

### iOS Permissions

```typescript
import {
  requestLocationPermissions,
  requestAlwaysLocationPermissions,
  hasLocationPermissions
} from 'rn_vietmap_tracking_plugin';

// Check current permissions
const checkPermissions = async () => {
  const hasBasic = await hasLocationPermissions();
  const alwaysResult = await requestAlwaysLocationPermissions();

  console.log('Basic permissions:', hasBasic);
  console.log('Always permissions:', alwaysResult);
};

// Request step-by-step permissions
const requestPermissionsSequence = async () => {
  // Step 1: Request basic location permission
  const basicResult = await requestLocationPermissions();
  if (basicResult !== 'granted') {
    throw new Error('Basic location permission required');
  }

  // Step 2: Request always location permission for background
  const alwaysResult = await requestAlwaysLocationPermissions();
  if (alwaysResult !== 'granted') {
    console.warn('Background tracking not available - always permission denied');
    return false;
  }

  return true;
};
```

### Android Permissions

Android permissions are handled automatically, but ensure your `AndroidManifest.xml` includes:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

## 🔄 App Lifecycle Management

### Background/Foreground Transitions

The plugin automatically handles app state changes:

```typescript
import { AppState } from 'react-native';

const handleAppStateChange = (nextAppState: string) => {
  if (nextAppState === 'background') {
    console.log('📱 App went to background - continuous tracking active');
  } else if (nextAppState === 'active') {
    console.log('📱 App became active - tracking continues seamlessly');
  }
};

AppState.addEventListener('change', handleAppStateChange);
```

## 📊 Advanced Usage Examples

### Real-time Route Tracking

```typescript
class RouteTracker {
  private route: LocationData[] = [];
  private subscription: any;

  async startRouteTracking() {
    // Start high-frequency background tracking
    await startTracking(true, 2000);

    this.subscription = addLocationUpdateListener((location) => {
      this.route.push(location);
      this.updateRouteStats();
    });
  }

  async stopRouteTracking() {
    await stopTracking();
    if (this.subscription) {
      this.subscription.remove();
    }
    return this.getRouteData();
  }

  private updateRouteStats() {
    const distance = this.calculateTotalDistance();
    const duration = this.calculateDuration();
    const avgSpeed = distance / (duration / 3600); // km/h

    console.log(`📊 Route stats: ${distance}km, ${duration}s, ${avgSpeed}km/h`);
  }

  private calculateTotalDistance(): number {
    let total = 0;
    for (let i = 1; i < this.route.length; i++) {
      const prev = this.route[i - 1];
      const curr = this.route[i];
      total += this.haversineDistance(prev, curr);
    }
    return total;
  }

  private haversineDistance(point1: LocationData, point2: LocationData): number {
    const R = 6371; // Earth's radius in km
    const dLat = (point2.latitude - point1.latitude) * Math.PI / 180;
    const dLon = (point2.longitude - point1.longitude) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(point1.latitude * Math.PI / 180) *
              Math.cos(point2.latitude * Math.PI / 180) *
              Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
  }
}
```

### Geofencing Implementation

```typescript
class GeofenceManager {
  private geofences: Array<{
    id: string;
    center: { lat: number; lng: number };
    radius: number; // meters
  }> = [];

  addGeofence(id: string, center: { lat: number; lng: number }, radius: number) {
    this.geofences.push({ id, center, radius });
  }

  checkGeofences(location: LocationData) {
    this.geofences.forEach(fence => {
      const distance = this.calculateDistance(
        location.latitude,
        location.longitude,
        fence.center.lat,
        fence.center.lng
      );

      if (distance <= fence.radius) {
        this.onGeofenceEnter(fence.id, location);
      }
    });
  }

  private onGeofenceEnter(fenceId: string, location: LocationData) {
    console.log(`🚩 Entered geofence ${fenceId} at ${location.latitude}, ${location.longitude}`);
    // Trigger custom logic
  }
}
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Background Tracking Stops After 30 Seconds (iOS)

**Problem**: Using timer-based approach instead of continuous updates.

**Solution**: Use the enhanced `startTracking()` method:
```typescript
// ❌ Don't use legacy timer-based tracking
await startLocationTracking(config);

// ✅ Use enhanced continuous tracking
await startTracking(true, 5000);
```

#### 2. Permission Denied for Background Tracking

**Problem**: App doesn't have "Always" location permission.

**Solution**: Request proper permissions:
```typescript
const result = await requestAlwaysLocationPermissions();
if (result !== 'granted') {
  // Guide user to settings
  Alert.alert(
    'Permission Required',
    'Please enable "Always" location access in Settings for background tracking.'
  );
}
```

#### 3. High Battery Consumption

**Problem**: Update interval too frequent or using high accuracy in background.

**Solution**: Optimize settings:
```typescript
// For background tracking, use reasonable intervals
await startTracking(true, 10000); // 10 seconds instead of 1 second

// The plugin automatically optimizes accuracy for background mode
```

#### 4. Android Background Restrictions

**Problem**: Android 10+ background location restrictions.

**Solution**: Ensure proper permissions and consider foreground service:
```xml
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

### iOS-Specific Configuration

#### Info.plist Requirements

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to track your GPS location when using the app.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs continuous location access to track your GPS location even when the app is in the background. This enables features like route tracking, delivery monitoring, and location-based services that work seamlessly while you use other apps.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>background-processing</string>
    <string>background-fetch</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.yourapp.background-location</string>
    <string>com.yourapp.location-sync</string>
</array>
```

### Android-Specific Configuration

#### AndroidManifest.xml Requirements

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<application>
    <service
        android:name="com.rnvietmaptrackingplugin.LocationTrackingService"
        android:foregroundServiceType="location"
        android:exported="false" />
</application>
```

## 📈 Performance Tips

### Battery Optimization

1. **Use Appropriate Intervals**: Don't update more frequently than needed
2. **Background Mode Only When Necessary**: Use foreground tracking when possible
3. **Let the Plugin Optimize**: The plugin automatically adjusts accuracy and filtering for background mode

### Memory Management

1. **Remove Listeners**: Always clean up location subscriptions
2. **Limit History**: Don't store unlimited location history in memory
3. **Process Data Efficiently**: Handle location updates asynchronously

```typescript
// Good practice for memory management
useEffect(() => {
  const subscription = addLocationUpdateListener(handleLocationUpdate);

  return () => {
    subscription?.remove(); // Always clean up
  };
}, []);
```

## 🆚 Migration from Legacy Methods

### From Timer-Based to Continuous Updates

```typescript
// ❌ Old way (timer-based, limited background support)
await startLocationTracking({
  intervalMs: 5000,
  backgroundMode: true,
  accuracy: 'high'
});

// ✅ New way (continuous updates, reliable background)
await startTracking(true, 5000);
```

### Benefits of Migration

1. **Reliable Background Tracking**: No 30-second limitation
2. **Better Battery Life**: Optimized power management
3. **Simpler API**: Fewer configuration options to manage
4. **Cross-Platform Consistency**: Same behavior on iOS and Android

## 🔍 Debugging

### Enable Debug Logging

```typescript
// The plugin automatically logs detailed information
// Check your console for messages like:
// 🚀 Starting enhanced tracking
// 📍 Location received
// 🌙 Background task chaining
// 🔋 Battery optimization enabled
```

### Testing Background Tracking

1. Start tracking with background mode enabled
2. Minimize the app (don't force close)
3. Check console logs for continuous location updates
4. Verify tracking continues beyond 30 seconds

```bash
# iOS Simulator
npx react-native run-ios

# Monitor logs
npx react-native log-ios
```

This comprehensive guide covers all aspects of using the RN VietMap Tracking Plugin with the enhanced background_location_2 strategy. For additional support, check the GitHub repository examples and issues.
