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

> **For production, prefer `initializeTracking`.** It checks the key against the
> server before configuring and rejects with `INVALID_API_KEY` when the key or
> host is wrong, where `configure` accepts whatever it is given and the mistake
> only surfaces later, at upload time. It also takes `authMode` and
> `autoUpload` — see [Auth mode](#auth-mode).
>
> ```typescript
> await initializeTracking('YOUR_VIETMAP_API_KEY', 'https://live.fleetwork.vn/api/v1');
> ```
>
> `configure` keeps working and needs no change if you already use it.

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
## 📚 Configuration

### Picking a tracking mode

`intervalMs` and `distanceFilter` choose the SDK's trigger **between them**.
Supply exactly one:

| supplied | behaviour |
|---|---|
| `intervalMs` only | timer — a fix every N ms, moving or not |
| `distanceFilter` only | displacement — a fix per N metres moved, none while stationary |
| both | the SDK favours the timer and **ignores** the distance gate |
| neither | the SDK's own defaults: a 10s timer with a 25m floor |

Omit the one you do not want. Passing `0` is a value, not an absence, and the
SDK clamps it up to its floor.

**Floors, enforced natively and silently:** `intervalMs` is raised to 5000 and
`distanceFilter` to 25. Intervals in the 5–10s band also have their uploads
coalesced to a single 10s cadence to avoid server rate limiting; GPS sampling is
unaffected.

### LocationTrackingConfig

```typescript
interface LocationTrackingConfig {
  /** Milliseconds between updates. Omit for distance-driven or SDK-default tracking. */
  intervalMs?: number;
  /** Metres between updates. Omit for timer-driven or SDK-default tracking. */
  distanceFilter?: number;
  accuracy?: 'high' | 'medium' | 'low';
  /** Defaults to true. Read once at start — stop and start again to change it. */
  backgroundMode?: boolean;
  /** Foreground service notification (Android only). */
  notificationTitle?: string;
  notificationMessage?: string;
  /** Required. Written into every upload as userId. */
  userId?: string;
  vehicleId?: string;
  /** Defaults to true. See "Fake GPS" below before changing it. */
  allowMockLocation?: boolean;
  /** Derive speed when the OS reports 0 or -1. Defaults to true. */
  enableSpeedFallback?: boolean;
  /** Opt in to battery-aware cadence. Defaults to false. */
  enableSmartBattery?: boolean;
  smartBatteryPreset?: 'navigation' | 'general' | 'batterySaver';
}
```

### Presets

```typescript
import { TRACKING_PRESETS, createSdkDefaultConfig } from '@vietmap/rn_vietmap_tracking_plugin';
```

| Preset | Trigger |
|---|---|
| `NAVIGATION` | 5s timer |
| `FITNESS` | 10s timer |
| `GENERAL` | 30s timer |
| `BATTERY_SAVER` | 5min timer |
| `NAVIGATION_DISTANCE` | 25m |
| `FITNESS_DISTANCE` | 50m |
| `GENERAL_DISTANCE` | 70m |
| `BATTERY_SAVER_DISTANCE` | 120m |

Every preset drives one trigger, never both. `createSdkDefaultConfig()` sets
neither, leaving the cadence to the SDK.

### Auth mode

```typescript
await initializeTracking(apiKey, baseURL, 'header', true);
```

`authMode` decides whether the API key travels as the `X-API-Key` header
(`'header'`, the default) or as `?apiKey=` (`'queryParam'`). The SDK reads it on
**every upload path**, so a mismatch with your gateway turns every upload into a
401 while tracking still looks perfectly healthy.

`autoUpload` defaults to `true`. Set it `false` to hold locations in the cache
and drive uploads yourself with `uploadCachedLocationsManually()`. It has no
effect on Android, where uploads are always automatic.

### Fake GPS

`allowMockLocation` defaults to **`true`**, which differs from the SDK's own
default of `false`. That is deliberate: the SDK drops every fix flagged as
simulated before tracking sees it, and on a simulator or emulator *every* fix is
simulated — so at `false` the demo silently uploads empty batches.

**In production, set it to `false`** and choose what happens on a detection:

```typescript
await setFakeGPSPolicy('warn');   // 'skip' | 'warn' | 'stopTracking' | 'logToServer'
await setFakeGpsNotificationConfig('Fake GPS detected', 'Location tracking paused.');

const subscription = addFakeGPSDetectedListener((event) => {
  console.log(event.lat, event.lng, event.reason); // reason is iOS-only
});
```

The **event** fires under every policy. The **notification** only fires under
`'warn'`. They are separate channels and are easy to conflate.

### Notifications: what the SDK does, and what your app owes it

**The native SDK posts the notification itself** — through
`UNUserNotificationCenter` on iOS and its own high-importance channel on
Android. It cannot, however, grant itself permission or decide how your app
presents notifications. Two things are yours:

**1. Permission.** Neither platform grants it implicitly, and **iOS never
prompts when a notification is posted** — with authorization still
`notDetermined` the post is dropped in silence. Ask in context, when the user
turns on something that notifies:

```typescript
if (!(await hasNotificationPermission())) {
  await requestNotificationPermission();
}
```

On Android this requests `POST_NOTIFICATIONS`, which your app must also declare:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**2. Foreground presentation, iOS only.** A notification posted while your app
is in the **foreground** is delivered and **not shown** unless you set a
`UNUserNotificationCenterDelegate`. Without it the SDK's post succeeds and looks
exactly like a failure — which is how most testing is done, with the app open.

The plugin deliberately does not do this for you:
`UNUserNotificationCenter.delegate` is a single app-wide slot, and a library
claiming it would break any app that has its own delegate. Add it to your
`AppDelegate`:

```swift
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    // ...
    return true
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound])
  }
}
```

**Debounce.** The SDK raises at most **one notification per 30 seconds**, so a
continuous stream of mock fixes cannot flood the tray. One banner per 30s is
working as intended.

Both points apply equally to the tracking-interrupted notification below.

### Tracking interruptions

```typescript
const subscription = addTrackingInterruptedListener((event) => {
  console.log(event.reason, event.recovered, event.secondsSinceLastFix);
});
```

**Do not stop and restart tracking in response.** The SDK raises these from GPS
silence, so a restart only costs a fresh first fix and can loop. Disabling the
notification does not silence the event — the callback channel fires either way.

### Offline cache

Locations are queued on device when the network is down and uploaded when it
returns. A `0` in `configureCacheLimits` keeps the SDK's own value for that
field, and those are **not identical across platforms**: `maxRecords` is 5000 on
Android and 10000 on iOS, while `maxDbSizeBytes` (50MB) and `batchSize` (50)
match.

```typescript
const pending = await getCachedLocationsCount();
if (pending > 0 && (await isNetworkConnected())) {
  await uploadCachedLocationsManually();
}
```

`uploadCachedLocationsManually` reports the upload result on iOS. Android's SDK
method returns nothing, so there it resolves `true` once the request has
started — check `getCachedLocationsCount()` afterwards to see what drained.

### App lifecycle

The plugin observes app state **natively on both platforms** — `UIApplication`
notifications on iOS, `LifecycleEventListener` on Android — and forwards it to
the SDK. It also reads the current state at registration, so a module created
while the app is already backgrounded does not leave the SDK believing
otherwise.

**Do not wire React Native's `AppState` to `onAppBackground`/`onAppForeground`.**
`AppState` is itself a native observer of the same notifications that then
crosses the bridge, so doing that delivers every transition twice — once
natively and once three hops later. The two methods stay exported only for a
host app that manages app state itself.

## 🛠️ API Reference

Every method below exists on both platforms unless the notes say otherwise.

### Configuration

| Method | Notes |
|---|---|
| `initializeTracking(apiKey, baseURL?, authMode?, autoUpload?)` | Validates the key server-side first. **Prefer this.** Rejects `INVALID_API_KEY`. |
| `configure(apiKey, baseURL?)` | Sets credentials without validating. Mistakes surface later, at upload time. |
| `configureAlertAPI(apiKey, apiID)` | Alert engine credentials. |
| `getPlatformVersion()` | `"iOS 18.0"` / `"Android 14"`. |

### Identity

| Method | Notes |
|---|---|
| `setDriverId(id)` / `getDriverId()` | Maps to the payload's `userId`. Also settable via the start config. |
| `setVehicleId(id)` / `getVehicleId()` | Optional. |
| `setMetadata(object)` | Arbitrary key-value data on every upload. |
| `setPackages(string[])` | Rejects non-string entries rather than coercing them. |
| `setAppSignature(string)` | |
| `configureVehicle({vehicleId, vehicleType, seats, weight, maxProvision?})` | Used by the alert engine. |

### Tracking

| Method | Notes |
|---|---|
| `startTracking(config)` | Requires `config.userId`. Returns `false` for a duplicate or already-active start rather than throwing. |
| `stopTracking()` | |
| `updateTrackingConfig(config)` | Cadence only. `backgroundMode` is read at start and cannot change mid-session. |
| `getCurrentLocation()` | |
| `isTrackingActive()` | |
| `getTrackingStatus()` | |
| `getTrackingHealthStatus()` | Permissions, uptime, time since the last fix. Assembled in the module on Android, which has no SDK method for it. |
| `getTrackingHistory({userId, fromTimestamp?, toTimestamp?, pageNumber?, pageSize?, sortBy?, sortDescending?})` | Timestamps are **milliseconds**; the Android SDK reads anything under 10 billion as seconds. |

### Permissions

| Method | Notes |
|---|---|
| `requestLocationPermissions()` | Returns a `PermissionResult`. |
| `hasLocationPermissions()` | |
| `requestAlwaysLocationPermissions()` | Required for background tracking. |

### Offline cache

| Method | Notes |
|---|---|
| `isNetworkConnected()` | The SDK's own view of the network. |
| `getCachedLocationsCount()` | |
| `uploadCachedLocationsManually()` | iOS reports the upload result; Android reports that it started. |
| `clearCachedLocations()` | |
| `configureCacheLimits({maxRecords?, maxDbSizeBytes?, batchSize?})` | A `0` or omitted field keeps the SDK's own value. |
| `getDatabaseSizeBytes()` | |

### Lifecycle

| Method | Notes |
|---|---|
| `onAppBackground()` / `onAppForeground()` | Driven natively. Do not wire `AppState` to these. |
| `setAutoUpload(enabled)` | iOS only; resolves `true` on Android, where uploads are always automatic. |

### Fake GPS

| Method | Notes |
|---|---|
| `setFakeGPSPolicy(policy)` | `'skip'` \| `'warn'` \| `'stopTracking'` \| `'logToServer'`. Only consulted while `allowMockLocation` is false. |
| `setFakeGpsNotificationConfig(title, message)` | Used by the `'warn'` policy. |
| `requestNotificationPermission()` | Required before any SDK notification can appear. iOS prompts once; Android requests `POST_NOTIFICATIONS` on API 33+ and resolves true below that. |
| `hasNotificationPermission()` | Current authorization state. |

### Tracking interrupted

| Method | Notes |
|---|---|
| `setTrackingInterruptedNotificationEnabled(enabled)` | Does **not** silence the event. |
| `setTrackingInterruptedNotificationConfig(title, message)` | |

### Other

| Method | Notes |
|---|---|
| `setSmartBatteryConfig(enabled, preset)` | Assembled in the plugin; neither SDK exposes it. |
| `processExternalLocation({lat, lng, speed, heading})` | `speed` at or below 30 is read as m/s, above that as km/h. |
| `turnOnAlert()` / `turnOffAlert()` | Alert engine. |

### Events

| Listener | Payload |
|---|---|
| `addLocationUpdateListener` | `LocationData` |
| `addTrackingStatusListener` | `TrackingStatus` |
| `addLocationErrorListener` | `{ message, timestamp }` |
| `addFakeGPSDetectedListener` | `FakeGpsEvent` — `reason` is iOS-only |
| `addTrackingInterruptedListener` | `TrackingInterruptedEvent` |

### Native SDK versions

| Platform | SDK |
|---|---|
| Android | `vietmap-tracking-sdk-android` 1.5.3 |
| iOS | `VietmapTrackingSDK` 1.5.2 |

### Detailed examples

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

## 🗂 Maintainer notes

`docs/` holds the working record behind this plugin — not user documentation,
but the reasoning that explains why parts of the code look the way they do.

| File | What it covers |
|---|---|
| [`docs/UPGRADE_PLAN.md`](docs/UPGRADE_PLAN.md) | 14 findings from the 0.1.4 → 0.2.0 work, each with the symptom that led to it |
| [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) | The 12-step plan, including what is still unverified |
| [`docs/FAKE_GPS_NOTIFICATION_PLAN.md`](docs/FAKE_GPS_NOTIFICATION_PLAN.md) | Who owns notification permission and presentation — the SDK posts, your app authorises |
| [`docs/TIMESTAMP_FIX_PLAN.md`](docs/TIMESTAMP_FIX_PLAN.md) | The millisecond convention and the object-shape audit |

Worth reading before "correcting" something that looks odd: several of those
oddities are deliberate, and the reason is written down there.

Releasing a new version: [`RELEASING.md`](RELEASING.md).

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
