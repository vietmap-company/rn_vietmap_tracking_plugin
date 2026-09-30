# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-09-30

Parity with `vietmap_flutter_tracking_plugin`: 23 new methods, two new events,
a reworked config layer and a rebuilt example app.

### Breaking

- **`LocationTrackingConfig.intervalMs` and `distanceFilter` are now optional.**
  They were required, so every start sent both — and the SDK resolves that by
  favouring the timer and ignoring the distance gate. Distance-driven tracking
  was therefore unreachable from React Native. Supply exactly one:

  | supplied            | behaviour                                        |
  |---------------------|--------------------------------------------------|
  | `intervalMs` only   | timer; a fix every N ms, moving or not           |
  | `distanceFilter` only | displacement; a fix per N metres moved         |
  | both                | the SDK favours the timer and ignores the distance |
  | neither             | the SDK's own defaults: 10s timer, 25m floor     |

  Passing `0` is a value, not an absence — omit the key instead.

- **`backgroundMode` now defaults to `true`**, matching the Flutter plugin. It
  previously defaulted to `false`.

- **`startTracking` takes `userId`** in its config and pushes it natively. The
  SDK refuses to start without one, and it reported that only through the status
  listener. `setDriverId` still works for callers that prefer it.

- **`TRACKING_PRESETS` values corrected.** `NAVIGATION` was 1000ms / 5m, both
  below the floors the SDK enforces (5000ms / 25m), so it was silently clamped
  and never did what it said. Every preset now drives one trigger, and the
  `_DISTANCE` variants are new.

- **`multiply` removed.** Scaffolding from the template.

- **`onRouteUpdate` removed** from `supportedEvents`. It was declared on both
  platforms and emitted on neither Android nor usefully on iOS; it belongs to
  the alert engine, which stays out of scope.

### Added

- **Auth mode.** `initializeTracking(apiKey, baseURL, authMode, autoUpload)`
  chooses whether the API key travels as the `X-API-Key` header or a `?apiKey=`
  query parameter. The SDK reads this on every upload path, so a mismatch with
  the gateway turns every upload into a 401 while tracking still looks healthy.
  Works on both platforms; the Flutter plugin wires it on iOS only.

- **Offline cache**: `isNetworkConnected`, `getCachedLocationsCount`,
  `uploadCachedLocationsManually`, `clearCachedLocations`,
  `configureCacheLimits`, `getDatabaseSizeBytes`.

- **Identity payload**: `setMetadata`, `setPackages`, `setAppSignature`,
  `configureVehicle`.

- **Lifecycle**: `onAppBackground`, `onAppForeground`, `setAutoUpload`. The
  plugin now drives app state **natively on both platforms** — `UIApplication`
  notifications on iOS, `LifecycleEventListener` on Android — so no host app
  needs to wire `AppState`, and doing so would double-fire. It also seeds the
  state at registration, so a module created while the app is already
  backgrounded does not leave the SDK believing otherwise.

- **Fake GPS**: `allowMockLocation` on the config (default `true`),
  `setFakeGPSPolicy`, `setFakeGpsNotificationConfig`, and the
  `onFakeGPSDetected` event on both platforms.

- **Tracking interrupted**: `setTrackingInterruptedNotificationEnabled`,
  `setTrackingInterruptedNotificationConfig`, and the `onTrackingInterrupted`
  event on both platforms. Do not stop and restart tracking in response — the
  SDK raises it from GPS silence, so a restart only costs a fresh first fix.

- **History and diagnostics**: `getTrackingHistory` (paginated),
  `getTrackingHealthStatus`. The Android SDK has no health method, so the module
  assembles it.

- **Smart battery**: `setSmartBatteryConfig`, plus `enableSmartBattery` on
  `startTracking` (opt-in).

- **Other**: `processExternalLocation`, `getPlatformVersion`,
  `createSdkDefaultConfig`, `addTrackingInterruptedListener`,
  `addFakeGPSDetectedListener`, `addLocationErrorListener`.

### Fixed

- **`allowMockLocation` was never set**, so the SDK's default `false` applied and
  every simulated fix was discarded before tracking saw it. On a simulator or
  emulator, where every fix is simulated, uploads went out as empty batches.

- **`updateTrackingConfig` was a no-op on iOS.** It wrote into a local
  dictionary and resolved `true` without telling the SDK anything.

- **`clearCachedLocations` was a stub on Android** that resolved `true` and
  cleared nothing.

- **Start guards.** `startTracking` now refuses a second concurrent start,
  checks `isTrackingActive` *before* requesting permissions so a redundant start
  cannot raise a permission dialog, and rejects when the SDK was never
  configured.

- **`TrackingPresets` was defined twice**, in `utils.ts` and `constants.ts`, with
  values that had already drifted apart. One definition now.

### Added — notifications

- **`requestNotificationPermission()` / `hasNotificationPermission()`.** The
  native SDK posts the fake-GPS and tracking-interrupted notifications itself
  and requires the host app to already hold authorization — and **iOS never
  prompts when a notification is posted**, so without this they were dropped in
  silence. On Android this requests `POST_NOTIFICATIONS` (API 33+).

  Permission is only half of it on iOS: a notification posted while your app is
  in the **foreground** is delivered and not shown unless you set a
  `UNUserNotificationCenterDelegate`. The plugin deliberately does not claim
  that delegate — it is app-wide state — so see the README for the
  `AppDelegate` snippet.

- **`addListener` / `removeListeners`.** `NativeEventEmitter` requires them and
  warned on every launch when absent. On Android with the new architecture they
  must exist or the emitter has nothing to call.

### Fixed — after the first round of testing

- **Android never showed the location permission dialog.** The request asked for
  `ACCESS_BACKGROUND_LOCATION` alongside foreground, and from Android 10 the
  system discards the **whole** request rather than the background part: the
  dialog appeared and was dismissed inside 70ms, and every permission came back
  denied. Android said so in logcat all along —
  *"For R+ apps, background permissions must be requested after foreground
  permissions are already granted"*. Now requests foreground only; background
  follows as a separate request once foreground is granted.

- **`getTrackingHealthStatus` returned the wrong shape on iOS.** The SDK's
  dictionary has 17 CoreLocation-specific fields and was forwarded as-is, so six
  of the eight fields this API declares were `undefined` and the one shared name
  was in seconds where the type says milliseconds. iOS now assembles the
  declared shape, keeping the SDK's own dictionary under `raw`.

- **`getTrackingStatus` was missing `trackingDuration` on Android**, although
  the type marks it required — arithmetic on it produced `NaN`.

- **`onTrackingInterrupted` carried an iOS-only `timestamp` in seconds** that
  the type never declared. Removed rather than converted: nothing read it,
  `secondsSinceLastFix` already carries the timing, and the Flutter plugin's
  event has the same four fields without it.

- **`onFakeGPSDetected` reported its timestamp in seconds on iOS and
  milliseconds on Android.** Both are milliseconds now, matching every other
  timestamp in this API. Android also sends `isFirstDetection`, which iOS
  already had.

- **Android logged driver ids and coordinates in release builds.** 44 `Log.d`
  calls had no `BuildConfig.DEBUG` guard, and Android does not strip them — a
  library cannot rely on the host app's R8 rules. All gated now; `Log.w` and
  `Log.e` stay, carrying no identity or position.

### Added — example app

- Split into 15 cards, with zustand for state.
- GPX replay through `processExternalLocation`, which the SDK routes into the
  real tracking pipeline — useful on a physical device, where `simctl location`
  and `adb emu geo fix` do not exist.
- userId, vehicleId and the applied package list persist across launches.
  Credentials, policy and config deliberately do not: they belong in source
  where they are reviewable.

### Internal

- `npm run validate` gained an iOS parity check. `RCT_EXTERN_METHOD` registers a
  selector without checking that Swift implements it, so a mismatch compiles
  cleanly and crashes at call time — that is how 14 methods stayed broken in
  0.1.x. The check compares both names and selector shapes.

- `npm run validate` also checks the codegen path in `Pods.xcodeproj`. React
  Native bakes the path to react-native there relative to the directory
  `pod install` ran from; run from anywhere but `example/ios` it climbs past the
  filesystem root and the next clean build fails. A warm DerivedData hides it,
  so the check reads the project file rather than trusting a build.

- `[VMLife]` lifecycle traces are DEBUG-gated on both platforms and stay. The
  `markJsAppState` measurement hook has been removed — see
  `docs/IMPLEMENTATION_PLAN.md` step 0.1.6.

### Supported versions

| | |
|---|---|
| React Native | 0.79.6 (minimum supported: see `docs/UPGRADE_PLAN.md`) |
| Android SDK | `vietmap-tracking-sdk-android` 1.5.3 |
| iOS SDK | `VietmapTrackingSDK` 1.5.2 |

## [0.1.4] - 2025-09-19

### Critical Fix
- Fixed severe iOS build errors in RnVietmapTrackingPluginModule.m
- Resolved "Missing context for method declaration" compilation errors
- Fixed "@end must appear in an Objective-C context" syntax errors
- Corrected Objective-C interface structure and method implementation placement

### Fixed
- Fixed critical Objective-C syntax errors preventing iOS compilation
- Resolved method declaration context issues in iOS module
- Fixed interface implementation structure for proper compilation
- Enhanced iOS module stability and build reliability

### Technical Improvements
- Corrected Objective-C method declaration context and implementation structure
- Improved iOS module implementation with proper category usage
- Enhanced build process stability for iOS platform
- Validated iOS compilation success across different architectures

### Build & Testing
- iOS build process now completes successfully without syntax errors
- Verified compilation on both arm64 and x86_64 architectures
- Cross-platform build stability maintained
- Production-ready iOS implementation achieved

## [1.0.3] - 2025-09-18

### Fixed
- Resolved final iOS TurboModule registration issues for production release
- Fixed module naming consistency across all platforms
- Enhanced backward compatibility with legacy module names
- Improved error handling for TurboModule initialization failures

## [0.1.2] - 2025-09-18

### Fixed
- Fixed iOS TurboModule registration and protocol implementation
- Resolved "RnVietmapTrackingPlugin could not be found" error on iOS
- Fixed Swift class to properly implement NativeRnVietmapTrackingPluginSpec protocol
- Added missing TurboModule extension for iOS implementation
- Completed iOS TurboModule architecture for New Architecture compatibility

### Technical Improvements
- Added proper TurboModule protocol conformance in Swift implementation
- Enhanced iOS module registration with correct protocol implementation
- Improved iOS build process with proper TurboModule integration
- Validated cross-platform functionality on both Android and iOS
- Successful build and runtime testing on both platforms

### Build & Testing
- iOS build process now completes successfully without TurboModule errors
- Android build remains stable with existing TurboModule implementation
- Example app runs successfully on both iOS and Android platforms
- Full validation suite passes including typecheck, lint, and tests

## [0.1.1] - 2025-09-18

### Fixed
- Fixed TurboModule registration issues on Android platform
- Resolved iOS Swift syntax errors with preprocessor directives
- Fixed TypeScript compilation errors in example application
- Updated ESLint configuration for proper TypeScript and JSX parsing
- Fixed missing accuracy property in LocationTrackingConfig objects
- Resolved Android TurboModule architecture compliance with generated specs

### Changed
- Migrated Android implementation to extend NativeRnVietmapTrackingPluginSpec
- Updated iOS implementation to remove C-style preprocessor directives in Swift
- Enhanced ESLint configuration with TypeScript parser support
- Improved build process with proper TurboModule architecture
- Updated dependencies for better compatibility

### Technical Improvements
- Complete TurboModule architecture implementation for both platforms
- Proper method signatures with Promise parameters on Android
- Clean Swift implementation without conditional compilation issues
- Comprehensive TypeScript type checking and validation
- Enhanced code quality enforcement with ESLint
- Successful cross-platform build and test validation

## [0.1.0] - 2025-09-18

### Added
- Initial release of React Native GPS Tracking Package
- Core location tracking functionality with native implementation
- Background location tracking support for Android and iOS
- Configurable tracking parameters (interval, distance filter, accuracy)
- Real-time location updates via event listeners
- Permission management for location access
- TypeScript support with comprehensive type definitions
- Validation functions for configuration and location data
- Utility functions for distance calculation, coordinate formatting, speed conversion
- Predefined tracking presets for common use cases (Navigation, Fitness, General, Battery Saver)
- Session tracking with statistics (duration, distance, average speed)
- Example application demonstrating all features
- Comprehensive documentation and usage guides

### Features
#### Core API
- `startLocationTracking(config)` - Start GPS tracking with configuration
- `stopLocationTracking()` - Stop GPS tracking
- `getCurrentLocation()` - Get current location immediately
- `isTrackingActive()` - Check if tracking is currently active
- `getTrackingStatus()` - Get detailed tracking status
- `updateTrackingConfig(config)` - Update configuration while tracking
- `requestLocationPermissions()` - Request location permissions
- `hasLocationPermissions()` - Check permission status
- `addLocationUpdateListener()` - Subscribe to location updates
- `addTrackingStatusListener()` - Subscribe to status changes
- `createDefaultConfig()` - Create default configuration

#### Utilities
- `LocationUtils` - Distance calculation, coordinate formatting, speed conversion, geofencing
- `TrackingSession` - Session management with statistics
- `TrackingPresets` - Predefined configurations for common use cases
- `validateLocationConfig()` - Configuration validation
- `normalizeLocationConfig()` - Configuration normalization
- `isValidCoordinate()` - Coordinate validation
- `isReasonableLocation()` - Location reasonableness check

#### Native Implementation
- **Android**: FusedLocationProviderClient with foreground service
- **iOS**: Core Location framework with background location support
- Battery optimized with configurable parameters
- Platform-specific optimizations and permission handling

#### Developer Experience
- Full TypeScript support with type definitions
- Comprehensive error handling and validation
- Detailed documentation with examples
- Testing utilities and validation functions
- Example app with complete feature demonstration
- Build and deployment scripts

### Platform Support
- Android 6.0+ (API 23+) with Google Play Services
- iOS 12.0+ with Core Location framework
- React Native 0.70+

### Dependencies
- Google Play Services Location (Android)
- Core Location framework (iOS)
- React Native TurboModules architecture

### Documentation
- Complete API reference
- Usage guide with examples
- Setup instructions for Android and iOS
- Troubleshooting guide
- Best practices and recommendations

### Testing
- Unit tests for utility functions
- Integration tests for validation
- Example app for manual testing
- Local testing scripts

### Build System
- React Native Builder Bob for package building
- TypeScript compilation with type checking
- ESLint for code quality
- Jest for testing
- Release automation scripts
