import { validateLocationConfig, normalizeLocationConfig, isValidCoordinate, isReasonableLocation } from '../validation';
import { TRACKING_PRESETS } from '../constants';
import { LocationUtils } from '../utils';

describe('GPS Tracking Package Tests', () => {
  // Test validation functions
  describe('validateLocationConfig', () => {
    test('should validate correct config', () => {
      const config = {
        intervalMs: 5000,
        distanceFilter: 10,
        accuracy: 'high' as const,
        backgroundMode: true,
        notificationTitle: 'Test',
        notificationMessage: 'Test Message'
      };

      const result = validateLocationConfig(config);
      expect(result.isValid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    test('should reject invalid interval', () => {
      const config = {
        intervalMs: 500, // Too low
        distanceFilter: 10,
        accuracy: 'high' as const,
        backgroundMode: true
      };

      const result = validateLocationConfig(config);
      expect(result.isValid).toBe(false);
      expect(result.errors).toContain('intervalMs must be at least 1000ms');
    });

    test('should reject invalid accuracy', () => {
      const config = {
        intervalMs: 5000,
        distanceFilter: 10,
        accuracy: 'invalid' as any,
        backgroundMode: true
      };

      const result = validateLocationConfig(config);
      expect(result.isValid).toBe(false);
      expect(result.errors.some(e => e.includes('accuracy must be one of'))).toBe(true);
    });
  });

  // Test normalization
  describe('normalizeLocationConfig', () => {
    test('should normalize invalid values', () => {
      const config = {
        intervalMs: 500, // Too low
        distanceFilter: -5, // Too low
        accuracy: 'invalid' as any,
        backgroundMode: undefined as any
      };

      const normalized = normalizeLocationConfig(config);
      expect(normalized.intervalMs).toBe(1000); // Min value
      expect(normalized.distanceFilter).toBe(0); // Min value
      expect(normalized.accuracy).toBe('high'); // Default
      expect(normalized.backgroundMode).toBe(false); // Boolean conversion
    });
  });

  // Test coordinate validation
  describe('isValidCoordinate', () => {
    test('should validate correct coordinates', () => {
      expect(isValidCoordinate(37.7749, -122.4194)).toBe(true); // San Francisco
      expect(isValidCoordinate(0, 0)).toBe(true); // Null Island
      expect(isValidCoordinate(90, 180)).toBe(true); // Extremes
      expect(isValidCoordinate(-90, -180)).toBe(true); // Extremes
    });

    test('should reject invalid coordinates', () => {
      expect(isValidCoordinate(91, 0)).toBe(false); // Lat too high
      expect(isValidCoordinate(-91, 0)).toBe(false); // Lat too low
      expect(isValidCoordinate(0, 181)).toBe(false); // Lon too high
      expect(isValidCoordinate(0, -181)).toBe(false); // Lon too low
    });
  });

  // Test location reasonableness
  describe('isReasonableLocation', () => {
    test('should accept reasonable location', () => {
      const location = {
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 100,
        accuracy: 10,
        speed: 5, // 5 m/s = 18 km/h
        bearing: 45,
        timestamp: Date.now()
      };

      expect(isReasonableLocation(location)).toBe(true);
    });

    test('should reject null island', () => {
      const location = {
        latitude: 0,
        longitude: 0,
        altitude: 0,
        accuracy: 10,
        speed: 0,
        bearing: 0,
        timestamp: Date.now()
      };

      expect(isReasonableLocation(location)).toBe(false);
    });

    test('should reject excessive speed', () => {
      const location = {
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 100,
        accuracy: 10,
        speed: 100, // 100 m/s = 360 km/h
        bearing: 45,
        timestamp: Date.now()
      };

      expect(isReasonableLocation(location)).toBe(false);
    });
  });

  // Test LocationUtils
  describe('LocationUtils', () => {
    test('should calculate distance correctly', () => {
      // Distance between San Francisco and Los Angeles (approximately 559 km)
      const sf = { lat: 37.7749, lon: -122.4194 };
      const la = { lat: 34.0522, lon: -118.2437 };

      const distance = LocationUtils.calculateDistance(sf.lat, sf.lon, la.lat, la.lon);
      expect(distance).toBeGreaterThan(550000); // 550 km
      expect(distance).toBeLessThan(570000); // 570 km
    });

    test('should format coordinates', () => {
      const formatted = LocationUtils.formatCoordinates(37.7749, -122.4194, 4);
      expect(formatted).toBe('37.7749, -122.4194');
    });

    test('should convert speed units', () => {
      const mps = 10; // 10 m/s
      const kmh = LocationUtils.mpsToKmh(mps);
      const mph = LocationUtils.mpsToMph(mps);

      expect(kmh).toBe(36); // 36 km/h
      expect(mph).toBeCloseTo(22.37, 1); // ~22.37 mph
    });

    test('should check geofence', () => {
      const center = { lat: 37.7749, lon: -122.4194 };
      const inside = { lat: 37.7750, lon: -122.4195 }; // Very close
      const outside = { lat: 37.8000, lon: -122.5000 }; // Far away

      const radius = 100; // 100 meters

      expect(LocationUtils.isWithinGeofence(
        inside.lat, inside.lon, center.lat, center.lon, radius
      )).toBe(true);

      expect(LocationUtils.isWithinGeofence(
        outside.lat, outside.lon, center.lat, center.lon, radius
      )).toBe(false);
    });
  });

  // Test presets
  describe('TRACKING_PRESETS', () => {
    test('should have valid presets', () => {
      Object.values(TRACKING_PRESETS).forEach(preset => {
        const result = validateLocationConfig(preset);
        expect(result.isValid).toBe(true);
      });
    });

    test('should have different intervals for different presets', () => {
      expect(TRACKING_PRESETS.NAVIGATION.intervalMs).toBeLessThan(TRACKING_PRESETS.FITNESS.intervalMs);
      expect(TRACKING_PRESETS.FITNESS.intervalMs).toBeLessThan(TRACKING_PRESETS.GENERAL.intervalMs);
      expect(TRACKING_PRESETS.GENERAL.intervalMs).toBeLessThan(TRACKING_PRESETS.BATTERY_SAVER.intervalMs);
    });
  });
});
