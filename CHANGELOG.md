# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
