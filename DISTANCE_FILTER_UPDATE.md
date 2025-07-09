# Distance Filter Feature Update

## Overview
Added new `distanceFilter` parameter to the `startTracking` API, allowing developers to customize the minimum distance threshold for location updates.

## Updated API Signature

### Before
```typescript
startTracking(backgroundMode: boolean, intervalMs: number, forceUpdateBackground?: boolean): Promise<string>
```

### After
```typescript
startTracking(
  backgroundMode: boolean,
  intervalMs: number = 5000,
  forceUpdateBackground: boolean = false,
  distanceFilter: number = 10
): Promise<string>
```

## Implementation Details

### Native Implementations
- **iOS**: Sets `locationManager.distanceFilter` for standard mode
- **Android**: Sets `LocationRequest.smallestDisplacement` for continuous updates
- **Force Mode**: Distance filter is ignored when `forceUpdateBackground: true`

### Configuration Examples
```typescript
// High precision navigation
await startTracking(true, 1000, false, 5);    // 1s interval, 5m distance filter

// Balanced tracking
await startTracking(true, 5000, false, 15);   // 5s interval, 15m distance filter

// Battery saver
await startTracking(true, 30000, false, 50);  // 30s interval, 50m distance filter

// Force mode (distance filter ignored)
await startTracking(true, 10000, true, 10);   // 10s forced intervals
```

## Documentation Updates

### README.md Updates
1. ✅ **Quick Start section** - Added distanceFilter parameter examples
2. ✅ **Enhanced Background Tracking** - Updated all code examples
3. ✅ **API Reference** - New Enhanced Tracking Methods section with full parameter documentation
4. ✅ **Force Update Background Mode** - Updated comparison table and examples
5. ✅ **Dual Tracking Mechanism** - Enhanced explanation with distance filter configuration
6. ✅ **Distance Filter Configuration Guide** - New section with use case recommendations
7. ✅ **Distance Filter Best Practices** - New section with dynamic filtering examples and pitfalls
8. ✅ **Recommended Usage** - Updated examples with appropriate distance filters

### Key Features Added to Documentation
- **Use Case Recommendations**: Navigation (5-10m), Fitness (10-15m), General (15-25m), Battery Saver (50-100m)
- **Dynamic Distance Filtering**: Code examples for adaptive filtering based on user activity
- **Common Pitfalls**: Guidance on avoiding too small/large filters
- **Scenario-based Examples**: Indoor, outdoor, vehicle, background monitoring configurations

## Backward Compatibility
✅ **Fully backward compatible** - `distanceFilter` parameter is optional with default value of 10 meters

## Usage Examples by Scenario

### Turn-by-turn Navigation
```typescript
await startTracking(false, 2000, false, 6);  // High precision, 6m threshold
```

### Fitness Tracking
```typescript
await startTracking(true, 10000, false, 12); // Balanced, 12m threshold
```

### Fleet/Delivery Tracking
```typescript
await startTracking(true, 15000, true, 5);   // Force mode, ignore distance filter
```

### Battery Conservation
```typescript
await startTracking(true, 120000, false, 75); // Long intervals, large distance threshold
```

## Benefits
1. **Battery Optimization**: Prevent updates from GPS noise and minor movements
2. **Customizable Precision**: Tune for specific use cases and requirements
3. **Cross-platform Consistency**: Same behavior on iOS and Android
4. **Smart Filtering**: Combined with timer throttling for optimal performance
5. **Developer Control**: Fine-tune tracking behavior without changing native code

## Next Steps
- Test the updated API with various distance filter values
- Monitor battery usage improvements with appropriate distance filters
- Consider implementing dynamic distance filtering based on user context
