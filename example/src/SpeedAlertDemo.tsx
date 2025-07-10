import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  ScrollView,
} from 'react-native';
import {
  addSpeedAlertListener,
  getCurrentLocation,
  type SpeedAlertEvent,
} from '../../src/index';

// Note: Route processing methods (processRouteData, getCurrentRouteInfo,
// findNearestAlert, checkSpeedViolation) are now handled purely at the
// native level (iOS/Android) and are not exposed through React Native.
// This demo now focuses on speed alert monitoring only.

const SpeedAlertDemo = () => {
  const [speedAlerts, setSpeedAlerts] = useState<SpeedAlertEvent[]>([]);
  const [currentLocation, setCurrentLocation] = useState<any>(null);
  const speedAlertSubscription = useRef<any>(null);

  React.useEffect(() => {
    // Subscribe to speed alert events
    speedAlertSubscription.current = addSpeedAlertListener((event: SpeedAlertEvent) => {
      console.log('🚨 Speed alert received:', event);
      setSpeedAlerts(prev => [event, ...prev.slice(0, 4)]); // Keep last 5 alerts
    });

    return () => {
      speedAlertSubscription.current?.remove();
    };
  }, []);

  const handleGetCurrentLocation = async () => {
    try {
      const location = await getCurrentLocation();
      setCurrentLocation(location);
      Alert.alert('✅ Success', `Location: ${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)}`);
    } catch (error) {
      console.error('Error getting location:', error);
      Alert.alert('❌ Error', 'Failed to get current location');
    }
  };

  const handleClearData = () => {
    setSpeedAlerts([]);
    setCurrentLocation(null);
  };

  return (
    <ScrollView style={styles.container}>
      <Text style={styles.title}>⚠️ Speed Alert Monitoring Demo</Text>

      <View style={styles.infoBox}>
        <Text style={styles.infoText}>
          <Text style={styles.bold}>Note:</Text> Route processing is now handled purely at the native level (iOS/Android).
          This demo shows speed alert monitoring functionality only.
        </Text>
      </View>

      {/* Action Buttons */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Actions</Text>

        <TouchableOpacity style={styles.button} onPress={handleGetCurrentLocation}>
          <Text style={styles.buttonText}>Get Current Location</Text>
        </TouchableOpacity>

        <TouchableOpacity style={[styles.button, styles.clearButton]} onPress={handleClearData}>
          <Text style={styles.buttonText}>Clear All Data</Text>
        </TouchableOpacity>
      </View>

      {/* Current Location */}
      {currentLocation && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>📍 Current Location</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Latitude:</Text> {currentLocation.latitude.toFixed(6)}
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Longitude:</Text> {currentLocation.longitude.toFixed(6)}
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Accuracy:</Text> {currentLocation.accuracy?.toFixed(1) || 'N/A'}m
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Speed:</Text> {currentLocation.speed?.toFixed(1) || 'N/A'} m/s
            </Text>
          </View>
        </View>
      )}

      {/* Speed Alerts History */}
      {speedAlerts.length > 0 && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>🚨 Recent Speed Alerts</Text>
          {speedAlerts.map((alert, index) => (
            <View key={index} style={[styles.infoBox, styles.alertBox]}>
              <Text style={styles.infoText}>
                <Text style={styles.bold}>Speed:</Text> {alert.currentSpeed.toFixed(1)} km/h
              </Text>
              <Text style={styles.infoText}>
                <Text style={styles.bold}>Limit:</Text> {alert.speedLimit} km/h
              </Text>
              <Text style={styles.infoText}>
                <Text style={styles.bold}>Excess:</Text> {alert.excess.toFixed(1)} km/h
              </Text>
              <Text style={styles.infoText}>
                <Text style={styles.bold}>Severity:</Text> {alert.severity}
              </Text>
              <Text style={styles.infoText}>
                <Text style={styles.bold}>Time:</Text> {new Date(alert.timestamp).toLocaleTimeString()}
              </Text>
            </View>
          ))}
        </View>
      )}

      {speedAlerts.length === 0 && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>📊 Status</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>No speed alerts received yet. Start driving to see alerts.</Text>
          </View>
        </View>
      )}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: '#f5f5f5',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 20,
    color: '#333',
  },
  section: {
    marginBottom: 20,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 10,
    color: '#333',
  },
  button: {
    backgroundColor: '#007AFF',
    padding: 15,
    borderRadius: 8,
    marginBottom: 10,
    alignItems: 'center',
  },
  clearButton: {
    backgroundColor: '#FF3B30',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  infoBox: {
    backgroundColor: 'white',
    padding: 15,
    borderRadius: 8,
    marginBottom: 10,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.22,
    shadowRadius: 2.22,
    elevation: 3,
  },
  alertBox: {
    borderLeftWidth: 4,
    borderLeftColor: '#FF3B30',
  },
  infoText: {
    fontSize: 14,
    marginBottom: 5,
    color: '#333',
  },
  bold: {
    fontWeight: 'bold',
  },
});

export default SpeedAlertDemo;
