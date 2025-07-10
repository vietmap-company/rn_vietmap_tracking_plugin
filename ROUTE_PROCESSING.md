# Route and Alert Processing Features

This document explains the new native route and alert processing capabilities added to the VietMap tracking plugin.

## Overview

The plugin now includes native processing of route data from VietMap API responses, including:
- Route link processing
- Alert detection and management
- Speed violation checking
- Real-time speed alerts

## API Response Format

The expected JSON format from your API should match this structure:

```json
{
  "links": [
    [linkId, direction, [startLat, startLon, endLat, endLon], distance, [[speedLimitFrom, speedLimitTo]]]
  ],
  "alerts": [
    [type, subtype, speedLimit, distance]
  ],
  "offset": [linkId, offsetDistance, direction]
}
```

## Usage Examples

**Important:** Route processing is now handled purely at the native level. Use the native module directly instead of wrapper functions.

### 1. Process Route Data

```typescript
import { RnVietmapTrackingPlugin } from 'rn_vietmap_tracking_plugin';

const routeJson = {
  "links": [
    [3084042, 1, [106.7008008157191, 10.728222624412965, 106.701535, 10.728238], 80, [[0, 60]]],
    // ... more links
  ],
  "alerts": [
    [0, 167, 60, 18], // type=0, subtype=167, speedLimit=60, distance=18
    // ... more alerts
  ],
  "offset": [3084042, 24, 1]
};

try {
  const processedData = await RnVietmapTrackingPlugin.processRouteData(routeJson);
  console.log('Processed route data:', processedData);
  console.log('Total links:', processedData.totalLinks);
  console.log('Total alerts:', processedData.totalAlerts);
} catch (error) {
  console.error('Failed to process route data:', error);
}
```

### 2. Find Nearest Alert

```typescript
import { RnVietmapTrackingPlugin, getCurrentLocation } from 'rn_vietmap_tracking_plugin';

try {
  // Get current location
  const location = await getCurrentLocation();

  // Find nearest alert based on current position
  const nearestAlert = await RnVietmapTrackingPlugin.findNearestAlert(location.latitude, location.longitude);

  console.log('Nearest link index:', nearestAlert.nearestLinkIndex);
  console.log('Distance to link:', nearestAlert.distanceToLink);
  console.log('Relevant alerts:', nearestAlert.alerts);
} catch (error) {
  console.error('Failed to find nearest alert:', error);
}
```

### 3. Check Speed Violations

```typescript
import { RnVietmapTrackingPlugin } from 'rn_vietmap_tracking_plugin';

try {
  // Current speed in m/s (70 km/h = 19.44 m/s)
  const speedMs = 70 / 3.6;

  const violation = await RnVietmapTrackingPlugin.checkSpeedViolation(speedMs);

  if (violation.isViolation) {
    console.log('🚨 SPEED VIOLATION!');
    console.log('Current speed:', violation.currentSpeed, 'km/h');
    console.log('Speed limit:', violation.speedLimit, 'km/h');
    console.log('Excess speed:', violation.excess, 'km/h');
  } else {
    console.log('✅ Speed within limits');
  }
} catch (error) {
  console.error('Failed to check speed violation:', error);
}
```

### 4. Listen for Speed Alerts

```typescript
import { addSpeedAlertListener } from 'rn_vietmap_tracking_plugin';

// Subscribe to real-time speed alerts
const subscription = addSpeedAlertListener((event) => {
  console.log('🚨 Speed alert received:', event);
  console.log('Current speed:', event.currentSpeed, 'km/h');
  console.log('Speed limit:', event.speedLimit, 'km/h');
  console.log('Severity:', event.severity); // 'warning' or 'critical'
  console.log('Excess:', event.excess, 'km/h');
});

// Remember to remove subscription when done
// subscription.remove();
```

### 5. Get Current Route Information

```typescript
import { RnVietmapTrackingPlugin } from 'rn_vietmap_tracking_plugin';

try {
  const routeInfo = await RnVietmapTrackingPlugin.getCurrentRouteInfo();
  console.log('Current route links:', routeInfo.links.length);
  console.log('Current route alerts:', routeInfo.alerts.length);
} catch (error) {
  console.error('No route data available:', error);
}
```

## Data Structures

### ProcessedRouteData
```typescript
interface ProcessedRouteData {
  links: RouteLink[];
  alerts: RouteAlert[];
  offset: any[];
  totalLinks: number;
  totalAlerts: number;
}
```

### RouteLink
```typescript
interface RouteLink {
  id: number;
  direction: number;
  startLat: number;
  startLon: number;
  endLat: number;
  endLon: number;
  distance: number;
  speedLimits: number[][];
}
```

### RouteAlert
```typescript
interface RouteAlert {
  type: number;
  subtype?: number;
  speedLimit?: number;
  distance: number;
}
```

### SpeedViolationResult
```typescript
interface SpeedViolationResult {
  isViolation: boolean;
  currentSpeed: number; // km/h
  speedLimit?: number; // km/h
  excess: number; // km/h
  alertInfo?: RouteAlert;
}
```

## Native Processing Benefits

1. **Performance**: Route calculations are performed natively for better performance
2. **Battery Efficiency**: Reduced JavaScript bridge calls
3. **Real-time Processing**: Immediate speed violation detection
4. **Memory Efficient**: Native memory management for large route datasets
5. **Pure Native**: All route processing happens at the native level without React Native wrapper functions

## Integration Workflow

1. **Initialize Route**: Call `RnVietmapTrackingPlugin.processRouteData()` with your API response
2. **Start Tracking**: Enable location tracking with speed alerts
3. **Monitor Violations**: Listen for speed alert events
4. **Update Route**: Process new route data when route changes
5. **Cleanup**: Remove listeners and clear route data when done

## Error Handling

All functions return promises and should be wrapped in try-catch blocks:

```typescript
try {
  const result = await RnVietmapTrackingPlugin.processRouteData(routeJson);
  // Handle success
} catch (error) {
  if (error.code === 'INVALID_DATA') {
    // Handle invalid route data
  } else if (error.code === 'NO_ROUTE_DATA') {
    // Handle missing route data
  } else {
    // Handle other errors
  }
}
```

## Demo Component

See `RouteProcessingDemo.tsx` for a complete example implementation showing all features in action.
