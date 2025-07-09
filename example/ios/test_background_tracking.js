/**
 * Enhanced test script to verify background location tracking functionality
 * Tests both foreground Timer-based tracking and background continuous tracking
 */
const script = `
import {NativeModules} from 'react-native';

// Test function to verify background tracking with Always permissions
async function testBackgroundTracking() {
    console.log('🧪 Starting enhanced background location tracking test...');

    try {
        // First check basic permissions
        const hasPermissions = await NativeModules.RnVietmapTrackingPlugin.hasLocationPermissions();
        console.log('📍 Has basic location permissions:', hasPermissions);

        if (!hasPermissions) {
            console.log('🔑 Requesting basic location permissions...');
            const permissionResult = await NativeModules.RnVietmapTrackingPlugin.requestLocationPermissions();
            console.log('🔑 Basic permission result:', permissionResult);

            // Wait a bit for permissions to be processed
            await new Promise(resolve => setTimeout(resolve, 2000));
        }

        // For background tracking, we need Always permissions
        console.log('🔐 Requesting Always location permissions for background tracking...');
        const alwaysPermissionResult = await NativeModules.RnVietmapTrackingPlugin.requestAlwaysLocationPermissions();
        console.log('🔐 Always permission result:', alwaysPermissionResult);

        if (alwaysPermissionResult === 'pending') {
            console.log('⏳ Please grant "Always" location permission in the iOS settings dialog that appeared');
            console.log('⏳ Then run this test again...');
            return;
        }

        if (alwaysPermissionResult !== 'granted') {
            console.log('❌ Always location permission not granted. Background tracking requires Always permission.');
            console.log('📝 Testing foreground-only mode instead...');
            await testForegroundTracking();
            return;
        }

        console.log('✅ Always permission granted! Testing background tracking...');
        await testBackgroundMode();

    } catch (error) {
        console.error('❌ Error in background tracking test:', error);
    }
}

// Test foreground tracking with timer
async function testForegroundTracking() {
    console.log('🌞 Testing foreground tracking with timer...');

    const config = {
        intervalMs: 8000, // 8 seconds for testing
        accuracy: 'high',
        distanceFilter: 5,
        backgroundMode: false
    };

    console.log('🚀 Starting foreground location tracking with config:', config);
    const result = await NativeModules.RnVietmapTrackingPlugin.startLocationTracking(config);
    console.log('✅ Foreground tracking started:', result);

    // Monitor for a few updates
    let checkCount = 0;
    const statusCheck = setInterval(async () => {
        checkCount++;
        const status = await NativeModules.RnVietmapTrackingPlugin.getTrackingStatus();
        console.log(\`📊 Foreground tracking status check \${checkCount}:\`, status);

        if (checkCount >= 4) { // Check for ~32 seconds
            clearInterval(statusCheck);
            console.log('✅ Foreground tracking test completed');
            console.log('🔄 Now testing background mode...');
            await testBackgroundMode();
        }
    }, 8000);
}

// Test background tracking with continuous updates
async function testBackgroundMode() {
    console.log('🌙 Testing background tracking with continuous updates...');

    // Stop any existing tracking first
    try {
        await NativeModules.RnVietmapTrackingPlugin.stopLocationTracking();
        await new Promise(resolve => setTimeout(resolve, 1000));
    } catch (e) {
        // Ignore if not tracking
    }

    const config = {
        intervalMs: 15000, // 15 seconds - background mode throttling
        accuracy: 'high',
        distanceFilter: 10, // Larger distance filter for background
        backgroundMode: true
    };

    console.log('🚀 Starting background location tracking with config:', config);
    const result = await NativeModules.RnVietmapTrackingPlugin.startLocationTracking(config);
    console.log('✅ Background tracking started:', result);

    // Check tracking status periodically
    let checkCount = 0;
    const statusCheck = setInterval(async () => {
        checkCount++;
        const status = await NativeModules.RnVietmapTrackingPlugin.getTrackingStatus();
        console.log(\`📊 Background tracking status check \${checkCount}:\`, status);

        if (checkCount >= 8) { // Check for 2 minutes
            clearInterval(statusCheck);
            console.log('✅ Background tracking test completed');
            console.log('🏠 NOW PUT THE APP IN BACKGROUND and check if location updates continue in the console');
            console.log('📱 To test: Press home button, wait 30 seconds, then return to app');
            console.log('🔍 Look for "Location received" messages while app was in background');
        }
    }, 15000);
}

// Run the test
testBackgroundTracking();
`;

console.log('📝 Created test script for background location tracking verification');
console.log('To run this test in the app:');
console.log('1. Open Chrome DevTools for React Native Debugger');
console.log('2. Copy and paste the script into the console');
console.log('3. Monitor the console for location updates and errors');
