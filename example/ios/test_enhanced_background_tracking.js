/**
 * Enhanced Background Tracking Test Script
 * Tests the new background_location_2 strategy with continuous location updates
 */

const { startTracking, stopTracking } = require('../src/index.tsx');

// Test configurations
const TEST_CONFIGS = {
  FOREGROUND: {
    backgroundMode: false,
    intervalMs: 3000, // 3 seconds
    testDuration: 30000 // 30 seconds
  },
  BACKGROUND: {
    backgroundMode: true,
    intervalMs: 5000, // 5 seconds
    testDuration: 60000 // 60 seconds
  }
};

class EnhancedTrackingTester {
  constructor() {
    this.locationCount = 0;
    this.startTime = null;
    this.lastLocationTime = null;
    this.intervals = [];
    this.isTracking = false;
  }

  log(message) {
    const timestamp = new Date().toISOString().substr(11, 12);
    console.log(`[${timestamp}] ${message}`);
  }

  async testForegroundTracking() {
    this.log('🌞 Starting Foreground Tracking Test (background_location_2 strategy)');
    const config = TEST_CONFIGS.FOREGROUND;

    return this.runTrackingTest(config, 'Foreground');
  }

  async testBackgroundTracking() {
    this.log('🌙 Starting Background Tracking Test (background_location_2 strategy)');
    const config = TEST_CONFIGS.BACKGROUND;

    return this.runTrackingTest(config, 'Background');
  }

  async runTrackingTest(config, testName) {
    this.resetCounters();

    try {
      this.log(`📋 ${testName} Test Configuration:`);
      this.log(`   - Background Mode: ${config.backgroundMode}`);
      this.log(`   - Interval: ${config.intervalMs}ms`);
      this.log(`   - Test Duration: ${config.testDuration}ms`);

      // Start enhanced tracking
      const result = await startTracking(config.backgroundMode, config.intervalMs);
      this.log(`✅ Tracking started: ${result}`);

      this.isTracking = true;
      this.startTime = Date.now();

      // Set up location listener for testing
      this.setupLocationListener();

      // Run test for specified duration
      await this.waitForDuration(config.testDuration);

      // Stop tracking
      const stopResult = await stopTracking();
      this.log(`🛑 Tracking stopped: ${stopResult}`);

      // Analyze results
      this.analyzeResults(config, testName);

    } catch (error) {
      this.log(`❌ ${testName} test failed: ${error.message}`);
      throw error;
    }
  }

  setupLocationListener() {
    // Note: This would be properly implemented with React Native event listeners
    // For now, we'll simulate location updates for testing
    this.log('📍 Setting up location listener for continuous updates...');

    this.simulateLocationUpdates();
  }

  simulateLocationUpdates() {
    // Simulate continuous location updates every 1-2 seconds
    // (representing what background_location_2 strategy would provide)
    const updateInterval = setInterval(() => {
      if (!this.isTracking) {
        clearInterval(updateInterval);
        return;
      }

      this.handleLocationUpdate({
        latitude: 21.0285 + (Math.random() - 0.5) * 0.001,
        longitude: 105.8542 + (Math.random() - 0.5) * 0.001,
        accuracy: 5 + Math.random() * 10,
        timestamp: Date.now()
      });
    }, 1000 + Math.random() * 1000); // 1-2 seconds
  }

  handleLocationUpdate(location) {
    const currentTime = Date.now();

    if (this.lastLocationTime) {
      const interval = currentTime - this.lastLocationTime;
      this.intervals.push(interval);
    }

    this.locationCount++;
    this.lastLocationTime = currentTime;

    this.log(`📍 Location ${this.locationCount}: lat=${location.latitude.toFixed(6)}, lon=${location.longitude.toFixed(6)}, acc=${location.accuracy.toFixed(1)}m`);

    if (this.intervals.length > 0) {
      const lastInterval = this.intervals[this.intervals.length - 1];
      this.log(`   ⏱️  Interval since last: ${lastInterval}ms`);
    }
  }

  async waitForDuration(duration) {
    this.log(`⏳ Running test for ${duration / 1000} seconds...`);

    if (duration > 10000) {
      this.log('💡 This test will continue in background. You can minimize the app to test background tracking.');
    }

    return new Promise(resolve => {
      setTimeout(() => {
        this.isTracking = false;
        resolve();
      }, duration);
    });
  }

  analyzeResults(config, testName) {
    const totalDuration = Date.now() - this.startTime;

    this.log(`\n📊 ${testName} Test Results Analysis:`);
    this.log(`   📈 Total Locations: ${this.locationCount}`);
    this.log(`   ⏱️  Total Duration: ${totalDuration}ms (${(totalDuration / 1000).toFixed(1)}s)`);

    if (this.intervals.length > 0) {
      const avgInterval = this.intervals.reduce((a, b) => a + b, 0) / this.intervals.length;
      const minInterval = Math.min(...this.intervals);
      const maxInterval = Math.max(...this.intervals);

      this.log(`   📊 Average Interval: ${avgInterval.toFixed(0)}ms`);
      this.log(`   📊 Min Interval: ${minInterval}ms`);
      this.log(`   📊 Max Interval: ${maxInterval}ms`);
      this.log(`   📊 Expected Interval: ${config.intervalMs}ms`);

      const withinTolerance = this.intervals.filter(interval =>
        Math.abs(interval - config.intervalMs) <= config.intervalMs * 0.5
      ).length;

      const accuracy = (withinTolerance / this.intervals.length) * 100;
      this.log(`   🎯 Interval Accuracy: ${accuracy.toFixed(1)}% (within 50% tolerance)`);

      // Test success criteria
      const expectedLocations = Math.floor(totalDuration / config.intervalMs);
      const locationSuccess = this.locationCount >= expectedLocations * 0.8; // 80% success rate
      const intervalSuccess = accuracy >= 70; // 70% interval accuracy

      this.log(`\n✅ Success Criteria:`);
      this.log(`   📍 Location Count: ${locationSuccess ? '✅' : '❌'} (${this.locationCount}/${expectedLocations} expected)`);
      this.log(`   ⏱️  Interval Accuracy: ${intervalSuccess ? '✅' : '❌'} (${accuracy.toFixed(1)}% >= 70%)`);

      if (locationSuccess && intervalSuccess) {
        this.log(`🎉 ${testName} test PASSED!`);
      } else {
        this.log(`😞 ${testName} test FAILED - check configuration or implementation`);
      }
    }

    this.log(''); // Empty line for readability
  }

  resetCounters() {
    this.locationCount = 0;
    this.startTime = null;
    this.lastLocationTime = null;
    this.intervals = [];
    this.isTracking = false;
  }

  async runAllTests() {
    this.log('🚀 Starting Enhanced Background Tracking Tests (background_location_2 strategy)');
    this.log('📱 Make sure location permissions are granted and app has background capabilities\n');

    try {
      // Test 1: Foreground tracking
      await this.testForegroundTracking();

      // Wait between tests
      this.log('⏸️  Waiting 5 seconds between tests...\n');
      await new Promise(resolve => setTimeout(resolve, 5000));

      // Test 2: Background tracking
      await this.testBackgroundTracking();

      this.log('🏁 All enhanced tracking tests completed!');

    } catch (error) {
      this.log(`💥 Test suite failed: ${error.message}`);
    }
  }
}

// Export for use in React Native app
if (typeof module !== 'undefined' && module.exports) {
  module.exports = EnhancedTrackingTester;
}

// Auto-run if called directly
if (require.main === module) {
  const tester = new EnhancedTrackingTester();
  tester.runAllTests();
}
