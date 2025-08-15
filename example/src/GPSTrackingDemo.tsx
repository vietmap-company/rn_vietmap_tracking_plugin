// @ts-ignore
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import React, { useState, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  ScrollView,
  TextInput,
  Switch,
  StatusBar,
} from 'react-native';
import {
  startTracking,
  stopTracking,
  getCurrentLocation,
  addLocationUpdateListener,
  addTrackingStatusListener,
  requestLocationPermissions,
  requestAlwaysLocationPermissions,
  hasLocationPermissions,
  updateTrackingConfig,
  turnOnAlert,
  turnOffAlert,
  configure,
  TrackingPresets,
  LocationUtils,
  TrackingSession,
  type LocationData,
  type TrackingStatus,
  type LocationTrackingConfig,
} from 'rn_vietmap_tracking_plugin';

const GPSTrackingDemo = () => {
  const [currentLocation, setCurrentLocation] = useState<LocationData | null>(null);
  const [isTracking, setIsTracking] = useState(false);
  const [hasPermissions, setHasPermissions] = useState(false);
  const [locationHistory, setLocationHistory] = useState<LocationData[]>([]);
  const [sessionStats, setSessionStats] = useState<any>(null);

  // Speed Alert state (native speech synthesis only - no event data to display)
  const [isSpeedAlertEnabled, setIsSpeedAlertEnabled] = useState(false);

  // Configuration state
  const [config, setConfig] = useState<LocationTrackingConfig>(TrackingPresets.GENERAL);
  const [customInterval, setCustomInterval] = useState('5000');
  const [customDistance, setCustomDistance] = useState('10');
  const [useCustomConfig, setUseCustomConfig] = useState(false);
  const [customBackgroundMode, setCustomBackgroundMode] = useState(false);

  const trackingSession = useRef(new TrackingSession());
  const locationSubscription = useRef<any>(null);
  const statusSubscription = useRef<any>(null);

  useEffect(() => {
    initializeTracking();
    return () => {
      cleanupSubscriptions();
    };
  }, []);

  const initializeTracking = async () => {
    try {
      // Configure VietmapTrackingSDK with API key
      console.log('🔧 Configuring VietmapTrackingSDK...');
      await configure('d18c0d40c7e7b75cd287b5a0e005edbdcd8772167a4f6140', 'http://192.168.22.154:5757', true);
      console.log('✅ VietmapTrackingSDK configured successfully');

      await checkPermissions();
      setupSubscriptions();
    } catch (error) {
      console.error('❌ Failed to initialize VietmapTrackingSDK:', error);
      Alert.alert('⚠️ Initialization Error', 'Failed to configure VietmapTrackingSDK. Please check your API key.');
    }
  };

  const setupSubscriptions = () => {
    // Location updates subscription
    locationSubscription.current = addLocationUpdateListener((location: LocationData) => {
      console.log('📍 Timer:', new Date(location.timestamp).toLocaleTimeString());
      console.log('📍 New location:', location);
      setCurrentLocation(location);
      setLocationHistory(prev => [...prev.slice(-49), location]); // Keep last 50 locations

      // Add to tracking session
      trackingSession.current.addLocation(
        location.latitude,
        location.longitude,
        location.timestamp
      );

      // Update session stats
      setSessionStats(trackingSession.current.getStats());
    });

    // Status updates subscription
    statusSubscription.current = addTrackingStatusListener((status: TrackingStatus) => {
      console.log('📊 Status update:', status);
      setIsTracking(status.isTracking);
    });
  };

  const cleanupSubscriptions = () => {
    if (locationSubscription.current) {
      locationSubscription.current.remove();
    }
    if (statusSubscription.current) {
      statusSubscription.current.remove();
    }
  };

  const checkPermissions = async () => {
    try {
      const permissions = await hasLocationPermissions();
      setHasPermissions(permissions.granted);
      console.log('🔒 Permissions status:', permissions);
    } catch (error) {
      console.error('Error checking permissions:', error);
    }
  };

  const handleRequestPermissions = async () => {
    try {
      const result = await requestLocationPermissions();
      console.log('🔓 Permission result:', result);
      if (result.granted) {
        setHasPermissions(true);
        Alert.alert('✅ Success', 'Location permissions granted');
      } else {
        Alert.alert('❌ Error', 'Location permissions denied');
      }
    } catch (error) {
      console.error('Error requesting permissions:', error);
      Alert.alert('❌ Error', 'Failed to request permissions');
    }
  };

  const getActiveConfig = (): LocationTrackingConfig => {
    if (useCustomConfig) {
      return {
        intervalMs: parseInt(customInterval) || 5000,
        distanceFilter: parseInt(customDistance) || 10,
        accuracy: config.accuracy,
        backgroundMode: customBackgroundMode,
        notificationTitle: config.notificationTitle,
        notificationMessage: config.notificationMessage,
      };
    }
    return config;
  };

  const handleStartTracking = async () => {
    if (!hasPermissions) {
      Alert.alert('⚠️ Warning', 'Location permissions required');
      return;
    }

    try {
      // Request always location permissions for background tracking
      console.log('🔐 Requesting always location permissions...');
      const alwaysPermissionResult = await requestAlwaysLocationPermissions();
      console.log('🔐 Always permission result:', alwaysPermissionResult);

      if (alwaysPermissionResult !== 'granted') {
        Alert.alert(
          '⚠️ Background Tracking',
          'Always location permission is recommended for background tracking.',
          [
            { text: 'Cancel', style: 'cancel', onPress: () => {} },
          ]
        );
        return;
      }

      await startTrackingWithConfig();
    } catch (error) {
      console.error('Error requesting always permissions:', error);
      Alert.alert('❌ Error', 'Failed to request always location permissions');
    }
  };

  const startTrackingWithConfig = async () => {
    try {
      const activeConfig = getActiveConfig();
      console.log('🚀 Starting enhanced tracking with config:', activeConfig);

      // Use enhanced tracking with location config
      const result = await startTracking(activeConfig);
      console.log('✅ Enhanced tracking result:', result);

      trackingSession.current.start();
      Alert.alert('✅ Success', 'Enhanced GPS tracking started');
    } catch (error) {
      console.error('Error starting enhanced tracking:', error);
      Alert.alert('❌ Error', 'Failed to start enhanced tracking');
    }
  };

  const handleStopTracking = async () => {
    try {
      const result = await stopTracking();
      console.log('✅ Enhanced tracking stopped:', result);

      trackingSession.current.clear();
      setSessionStats(null);
      Alert.alert('✅ Success', 'Enhanced GPS tracking stopped');
    } catch (error) {
      console.error('Error stopping enhanced tracking:', error);
      Alert.alert('❌ Error', 'Failed to stop enhanced tracking');
    }
  };

  const handleGetCurrentLocation = async () => {
    try {
      const location = await getCurrentLocation();
      setCurrentLocation(location);
      const formatted = LocationUtils.formatCoordinates(location.latitude, location.longitude);
      Alert.alert('📍 Current Location', formatted);
    } catch (error) {
      console.error('Error getting location:', error);
      Alert.alert('❌ Error', 'Failed to get current location');
    }
  };

  const handleUpdateConfig = async () => {
    if (!isTracking) {
      Alert.alert('⚠️ Warning', 'Start tracking first');
      return;
    }

    try {
      const activeConfig = getActiveConfig();
      const success = await updateTrackingConfig(activeConfig);
      if (success) {
        Alert.alert('✅ Success', 'Configuration updated');
      }
    } catch (error) {
      console.error('Error updating config:', error);
      Alert.alert('❌ Error', 'Failed to update configuration');
    }
  };

  const handleClearHistory = () => {
    setLocationHistory([]);
    setSessionStats(null);
    trackingSession.current.clear();
  };

  const handleSpeedAlertToggle = async (enabled: boolean) => {
    try {
      if (enabled) {
        // Turn on speed alert
        const success = await turnOnAlert();
        if (success) {
          setIsSpeedAlertEnabled(true);
        } else {
          Alert.alert('❌ Error', 'Failed to turn on speed alert');
        }
      } else {
        // Turn off speed alert
        const success = await turnOffAlert();
        if (success) {
          setIsSpeedAlertEnabled(false);
        } else {
          Alert.alert('❌ Error', 'Failed to turn off speed alert');
        }
      }
    } catch (error) {
      console.error('Error toggling speed alert:', error);
      Alert.alert('❌ Error', 'Failed to toggle speed alert');
    }
  };

  const calculateTotalDistance = () => {
    if (locationHistory.length < 2) return 0;

    let totalDistance = 0;
    for (let i = 1; i < locationHistory.length; i++) {
      const prev = locationHistory[i - 1];
      const current = locationHistory[i];
      if (prev && current) {
        totalDistance += LocationUtils.calculateDistance(
          prev.latitude, prev.longitude,
          current.latitude, current.longitude
        );
      }
    }
    return totalDistance;
  };

  const formatDuration = (ms: number) => {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (hours > 0) {
      return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
    } else if (minutes > 0) {
      return `${minutes}m ${seconds % 60}s`;
    } else {
      return `${seconds}s`;
    }
  };

  const PresetButton = ({ preset, name, onPress }: any) => (
    <TouchableOpacity
      style={[styles.presetButton, config === preset && styles.activePreset]}
      onPress={onPress}
    >
      <Text style={[styles.presetButtonText, config === preset && styles.activePresetText]}>
        {name}
      </Text>
    </TouchableOpacity>
  );

  return (
    <ScrollView style={styles.container}>
      <StatusBar barStyle="dark-content" backgroundColor="#f8f9fa" />

      <View style={styles.header}>
        <Text style={styles.title}>🛰️ GPS Tracking Demo</Text>
        <View style={styles.statusRow}>
          <Text style={styles.statusLabel}>Status:</Text>
          <Text style={[styles.statusValue, isTracking ? styles.active : styles.inactive]}>
            {isTracking ? '🟢 Active' : '🔴 Inactive'}
          </Text>
        </View>
        <View style={styles.statusRow}>
          <Text style={styles.statusLabel}>Permissions:</Text>
          <Text style={[styles.statusValue, hasPermissions ? styles.granted : styles.denied]}>
            {hasPermissions ? '✅ Granted' : '❌ Denied'}
          </Text>
        </View>
      </View>

      {/* Permission Section */}
      {!hasPermissions && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>🔒 Permissions</Text>
          <TouchableOpacity style={styles.button} onPress={handleRequestPermissions}>
            <Text style={styles.buttonText}>Request Location Permissions</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Speed Alert Section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>🚨 Speed Alert</Text>
        <View style={styles.switchRow}>
          <Text style={styles.label}>Enable Speed Alert:</Text>
          <Switch
            value={isSpeedAlertEnabled}
            onValueChange={handleSpeedAlertToggle}
          />
        </View>

        <Text style={styles.label}>
          Speed violations are announced using native speech synthesis.
          No visual alerts are displayed.
        </Text>
      </View>

      {/* Configuration Section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>⚙️ Configuration</Text>

        <View style={styles.presetContainer}>
          <Text style={styles.label}>Presets:</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            <PresetButton
              preset={TrackingPresets.NAVIGATION}
              name="Navigation"
              onPress={() => setConfig(TrackingPresets.NAVIGATION)}
            />
            <PresetButton
              preset={TrackingPresets.FITNESS}
              name="Fitness"
              onPress={() => setConfig(TrackingPresets.FITNESS)}
            />
            <PresetButton
              preset={TrackingPresets.GENERAL}
              name="General"
              onPress={() => setConfig(TrackingPresets.GENERAL)}
            />
            <PresetButton
              preset={TrackingPresets.BATTERY_SAVER}
              name="Battery Saver"
              onPress={() => setConfig(TrackingPresets.BATTERY_SAVER)}
            />
          </ScrollView>
        </View>

        <View style={styles.customConfigContainer}>
          <View style={styles.switchRow}>
            <Text style={styles.label}>Use Custom Config:</Text>
            <Switch
              value={useCustomConfig}
              onValueChange={setUseCustomConfig}
            />
          </View>

          {useCustomConfig && (
            <View style={styles.customInputs}>
              <View style={styles.inputRow}>
                <Text style={styles.inputLabel}>Interval (ms):</Text>
                <TextInput
                  style={styles.input}
                  value={customInterval}
                  onChangeText={setCustomInterval}
                  keyboardType="numeric"
                  placeholder="5000"
                />
              </View>
              <View style={styles.inputRow}>
                <Text style={styles.inputLabel}>Distance (m):</Text>
                <TextInput
                  style={styles.input}
                  value={customDistance}
                  onChangeText={setCustomDistance}
                  keyboardType="numeric"
                  placeholder="10"
                />
              </View>

              <View style={styles.switchRow}>
                <Text style={styles.label}>Background Mode (Custom):</Text>
                <Switch
                  value={customBackgroundMode}
                  onValueChange={setCustomBackgroundMode}
                />
              </View>
            </View>
          )}
        </View>

        <View style={styles.configInfo}>
          <Text style={styles.configText}>
            Current: {useCustomConfig ? 'Custom' : 'Preset'} |
            Interval: {getActiveConfig().intervalMs}ms |
            Distance: {getActiveConfig().distanceFilter}m |
            Accuracy: {getActiveConfig().accuracy} |
            Background: {getActiveConfig().backgroundMode ? '✅' : '❌'} |
          </Text>
        </View>
      </View>

      {/* Control Section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>🎮 Controls</Text>

        <View style={styles.buttonRow}>
          <TouchableOpacity
            style={[styles.button, styles.startButton, (!hasPermissions || isTracking) && styles.disabledButton]}
            onPress={handleStartTracking}
            disabled={!hasPermissions || isTracking}
          >
            <Text style={styles.buttonText}>🚀 Start Tracking</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.button, styles.stopButton, !isTracking && styles.disabledButton]}
            onPress={handleStopTracking}
            disabled={!isTracking}
          >
            <Text style={styles.buttonText}>🛑 Stop Tracking</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.buttonRow}>
          <TouchableOpacity
            style={[styles.button, !hasPermissions && styles.disabledButton]}
            onPress={handleGetCurrentLocation}
            disabled={!hasPermissions}
          >
            <Text style={styles.buttonText}>📍 Get Location</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.button, !isTracking && styles.disabledButton]}
            onPress={handleUpdateConfig}
            disabled={!isTracking}
          >
            <Text style={styles.buttonText}>⚙️ Update Config</Text>
          </TouchableOpacity>
        </View>

        <TouchableOpacity
          style={[styles.button, styles.clearButton]}
          onPress={handleClearHistory}
        >
          <Text style={styles.buttonText}>🗑️ Clear History</Text>
        </TouchableOpacity>
      </View>

      {/* Current Location Section */}
      {currentLocation && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>📍 Current Location</Text>
          <View style={styles.locationInfo}>
            <Text style={styles.locationText}>
              <Text style={styles.bold}>Coordinates:</Text> {LocationUtils.formatCoordinates(currentLocation.latitude, currentLocation.longitude)}
            </Text>
            <Text style={styles.locationText}>
              <Text style={styles.bold}>Altitude:</Text> {currentLocation.altitude.toFixed(2)}m
            </Text>
            <Text style={styles.locationText}>
              <Text style={styles.bold}>Accuracy:</Text> {currentLocation.accuracy.toFixed(2)}m
            </Text>
            <Text style={styles.locationText}>
              <Text style={styles.bold}>Speed:</Text> {LocationUtils.mpsToKmh(currentLocation.speed).toFixed(2)} km/h
            </Text>
            <Text style={styles.locationText}>
              <Text style={styles.bold}>Bearing:</Text> {currentLocation.bearing.toFixed(2)}°
            </Text>
            <Text style={styles.locationText}>
              <Text style={styles.bold}>Time:</Text> {new Date(currentLocation.timestamp).toLocaleString()}
            </Text>
          </View>
        </View>
      )}

      {/* Session Stats Section */}
      {sessionStats && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>📊 Session Statistics</Text>
          <View style={styles.statsContainer}>
            <View style={styles.statItem}>
              <Text style={styles.statLabel}>Duration</Text>
              <Text style={styles.statValue}>{formatDuration(sessionStats.duration)}</Text>
            </View>
            <View style={styles.statItem}>
              <Text style={styles.statLabel}>Distance</Text>
              <Text style={styles.statValue}>{(sessionStats.distance / 1000).toFixed(2)} km</Text>
            </View>
            <View style={styles.statItem}>
              <Text style={styles.statLabel}>Avg Speed</Text>
              <Text style={styles.statValue}>{LocationUtils.mpsToKmh(sessionStats.averageSpeed).toFixed(2)} km/h</Text>
            </View>
            <View style={styles.statItem}>
              <Text style={styles.statLabel}>Points</Text>
              <Text style={styles.statValue}>{sessionStats.locationCount}</Text>
            </View>
          </View>
        </View>
      )}

      {/* Location History Section */}
      {locationHistory.length > 0 && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>📝 Location History ({locationHistory.length})</Text>
          <View style={styles.historyContainer}>
            {locationHistory.slice(-5).reverse().map((location, index) => (
              <View key={index} style={styles.historyItem}>
                <Text style={styles.historyText}>
                  {LocationUtils.formatCoordinates(location.latitude, location.longitude)} |
                  {LocationUtils.mpsToKmh(location.speed).toFixed(1)} km/h |
                  {new Date(location.timestamp).toLocaleTimeString()}
                </Text>
              </View>
            ))}
          </View>
          <Text style={styles.totalDistance}>
            Total Distance: {(calculateTotalDistance() / 1000).toFixed(2)} km
          </Text>
        </View>
      )}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
  },
  header: {
    backgroundColor: '#fff',
    padding: 20,
    borderBottomWidth: 1,
    borderBottomColor: '#e9ecef',
    marginBottom: 10,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 15,
    color: '#2c3e50',
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 2,
  },
  statusLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: '#495057',
    width: 100,
  },
  statusValue: {
    fontSize: 16,
    fontWeight: 'bold',
  },
  active: {
    color: '#28a745',
  },
  inactive: {
    color: '#dc3545',
  },
  granted: {
    color: '#28a745',
  },
  denied: {
    color: '#dc3545',
  },
  section: {
    backgroundColor: '#fff',
    margin: 10,
    padding: 15,
    borderRadius: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 15,
    color: '#2c3e50',
  },
  presetContainer: {
    marginBottom: 15,
  },
  label: {
    fontSize: 16,
    fontWeight: '600',
    color: '#495057',
    marginBottom: 8,
  },
  presetButton: {
    backgroundColor: '#e9ecef',
    paddingHorizontal: 15,
    paddingVertical: 8,
    borderRadius: 20,
    marginRight: 10,
  },
  activePreset: {
    backgroundColor: '#007bff',
  },
  presetButtonText: {
    fontSize: 14,
    color: '#495057',
  },
  activePresetText: {
    color: '#fff',
  },
  customConfigContainer: {
    marginBottom: 15,
  },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 10,
  },
  customInputs: {
    backgroundColor: '#f8f9fa',
    padding: 15,
    borderRadius: 8,
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  inputLabel: {
    fontSize: 14,
    color: '#495057',
    width: 100,
  },
  input: {
    flex: 1,
    borderWidth: 1,
    borderColor: '#ced4da',
    borderRadius: 6,
    paddingHorizontal: 10,
    paddingVertical: 8,
    backgroundColor: '#fff',
  },
  configInfo: {
    backgroundColor: '#f8f9fa',
    padding: 10,
    borderRadius: 6,
  },
  configText: {
    fontSize: 12,
    color: '#6c757d',
    textAlign: 'center',
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 10,
  },
  button: {
    backgroundColor: '#007bff',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 8,
    flex: 1,
    marginHorizontal: 5,
  },
  startButton: {
    backgroundColor: '#28a745',
  },
  stopButton: {
    backgroundColor: '#dc3545',
  },
  clearButton: {
    backgroundColor: '#6c757d',
    marginHorizontal: 5,
  },
  disabledButton: {
    backgroundColor: '#6c757d',
    opacity: 0.6,
  },
  buttonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'center',
  },
  locationInfo: {
    backgroundColor: '#f8f9fa',
    padding: 15,
    borderRadius: 8,
  },
  locationText: {
    fontSize: 14,
    color: '#495057',
    marginBottom: 5,
  },
  bold: {
    fontWeight: 'bold',
  },
  statsContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
  },
  statItem: {
    backgroundColor: '#f8f9fa',
    padding: 15,
    borderRadius: 8,
    width: '48%',
    marginBottom: 10,
    alignItems: 'center',
  },
  statLabel: {
    fontSize: 12,
    color: '#6c757d',
    marginBottom: 5,
  },
  statValue: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#2c3e50',
  },
  historyContainer: {
    maxHeight: 200,
  },
  historyItem: {
    backgroundColor: '#f8f9fa',
    padding: 10,
    borderRadius: 6,
    marginBottom: 5,
  },
  historyText: {
    fontSize: 12,
    color: '#495057',
  },
  totalDistance: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#007bff',
    textAlign: 'center',
    marginTop: 10,
  },
  alertInfo: {
    backgroundColor: '#fff3cd',
    padding: 10,
    borderRadius: 6,
    marginTop: 10,
  },
  alertText: {
    fontSize: 14,
    color: '#856404',
  },
});

export default GPSTrackingDemo;
