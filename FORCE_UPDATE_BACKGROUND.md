# Force Update Background Feature

## Overview

The `forceUpdateBackground` option provides continuous GPS tracking that bypasses iOS background location limitations by using timer-based location requests instead of relying on distance filters and system throttling.

## Problem Solved

**iOS Background Location Issue**:
- Standard background location tracking works well for 10-30 minutes
- After this period, iOS system throttles location updates significantly
- Updates become sporadic and unreliable during extended background periods
- Distance-based filtering may miss location updates when user is stationary

**Solution**:
Force update mode uses timer-based location requests that bypass iOS distance filtering and system throttling, providing continuous location updates regardless of movement patterns or iOS limitations.

## API Usage

```typescript
import { startTracking, stopTracking } from 'rn_vietmap_tracking_plugin';

// Standard background tracking (subject to iOS throttling)
await startTracking(
  true,    // backgroundMode
  30000,   // intervalMs - 30 seconds
  false    // forceUpdateBackground - use distance filter
);

// Force background tracking (bypasses iOS throttling)
await startTracking(
  true,    // backgroundMode
  10000,   // intervalMs - 10 seconds
  true     // forceUpdateBackground - force timer updates
);
```

## Implementation Details

### iOS Implementation

**Standard Mode (`forceUpdateBackground: false`)**:
```swift
// Uses distance filter + timer throttling
locationManager.distanceFilter = 10 // meters
locationManager.startUpdatingLocation()
// iOS calls didUpdateLocations when movement >= 10m
// Plugin throttles based on intervalMs
```

**Force Mode (`forceUpdateBackground: true`)**:
```swift
// Uses timer + direct location requests
locationManager.distanceFilter = kCLDistanceFilterNone
Timer.scheduledTimer(withTimeInterval: intervalMs) {
    locationManager.requestLocation() // Force location request
}
// Always sends updates regardless of movement
```

### Android Implementation

**Standard Mode**:
```kotlin
// Continuous updates with throttling
LocationRequest.create().apply {
    interval = 1000L // 1 second intervals
    smallestDisplacement = 10f // 10 meter distance filter
}
// Plugin throttles in handleLocationUpdate()
```

**Force Mode**:
```kotlin
// Timer-based forced requests
Timer().scheduleAtFixedRate(intervalMs) {
    fusedLocationClient.lastLocation // Request current location
}
// No distance filtering, always sends updates
```

## Performance Comparison

| Mode | Battery Impact | Reliability | Movement Detection | Stationary Tracking |
|------|----------------|-------------|-------------------|-------------------|
| **Standard** | Low | Good (10-30 min) | Excellent | Poor |
| **Force** | Medium-High | Excellent | Good | Excellent |

## Use Cases

### When to Use Force Mode:
- **Delivery/Transportation**: Continuous tracking for logistics
- **Emergency Services**: Critical location monitoring
- **Asset Tracking**: Stationary vehicle monitoring
- **Scientific Data Collection**: Precise timing requirements

### When to Use Standard Mode:
- **Fitness Apps**: Activity-based tracking
- **General Location Services**: Casual location monitoring
- **Battery-Sensitive Apps**: Power conservation priority

## Configuration Examples

```typescript
// Delivery tracking - high reliability needed
await startTracking(true, 15000, true);  // 15s forced updates

// Fitness tracking - movement-based
await startTracking(true, 30000, false); // 30s distance-filtered

// Emergency services - maximum reliability
await startTracking(true, 5000, true);   // 5s forced updates

// Battery saver - minimal tracking
await startTracking(true, 300000, false); // 5min distance-filtered
```

## Implementation Files

### TypeScript Interface:
- `src/NativeRnVietmapTrackingPlugin.ts` - Added forceUpdateBackground parameter
- `src/index.tsx` - Updated startTracking function signature

### iOS Native:
- `ios/RnVietmapTrackingPlugin.swift` - Added force update mode logic
- `ios/RnVietmapTrackingPluginModule.m` - Updated bridge method

### Android Native:
- `android/.../RnVietmapTrackingPluginModule.kt` - Added timer-based tracking

### Example App:
- `example/src/GPSTrackingDemo.tsx` - Added UI switch for testing

## Testing

The feature can be tested using the example app:

1. Enable "Force Update Background" switch
2. Start tracking with background mode
3. Put app in background
4. Monitor continuous location updates in logs

Expected behavior:
- Force mode: Continuous updates every intervalMs
- Standard mode: Updates may become sporadic after 30+ minutes

## Limitations

1. **Higher Battery Usage**: Timer-based requests consume more power
2. **Duplicate Locations**: May receive same coordinates when stationary
3. **iOS Only Optimization**: Feature primarily addresses iOS limitations
4. **Timing Precision**: Actual intervals may vary slightly due to system scheduling

## Migration Guide

### From Standard to Force Mode:
```typescript
// Before
await startTracking(true, 30000);

// After
await startTracking(true, 30000, true);
```

### Backward Compatibility:
```typescript
// Old API still works (forceUpdateBackground defaults to false)
await startTracking(true, 30000);
// Equivalent to:
await startTracking(true, 30000, false);
```

## Conclusion

The `forceUpdateBackground` feature provides a robust solution for applications requiring continuous background location tracking, especially on iOS where system limitations can affect reliability during extended background periods.
