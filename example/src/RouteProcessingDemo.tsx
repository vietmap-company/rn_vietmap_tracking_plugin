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

// Sample JSON data from your API
const SAMPLE_ROUTE_DATA = {
  "links": [
    [3084042, 1, [106.7008008157191, 10.728222624412965, 106.701535, 10.728238], 80, [[0, 60]]],
    [3097857, 1, [106.701535, 10.728238, 106.70235, 10.728245], 89, [[0, 60]]],
    [4659, 1, [106.70235, 10.728245, 106.703285, 10.728254], 102, [[0, 60]]],
    [3378, 1, [106.703285, 10.728254, 106.704197, 10.728271], 99, [[0, 60]]],
    [3134099, 1, [106.704197, 10.728271, 106.705073, 10.728287], 95, [[0, 60]]],
    [3276, 1, [106.705073, 10.728287, 106.706819, 10.728338], 190, [[0, 60]]],
    [3379, 1, [106.706819, 10.728338, 106.708625, 10.728372], 197, [[0, 60]]],
    [3226, 1, [106.708625, 10.728372, 106.712313, 10.728441], 402, [[0, 60]]]
  ],
  "alerts": [
    [0, 167, 60, 18],
    [0, 211, null, 185],
    [1, 1, null, 253],
    [2, null, null, 271],
    [0, 169, null, 293],
    [0, 167, 60, 320],
    [0, 169, null, 478],
    [0, 167, 60, 489],
    [0, 68, null, 499],
    [0, 68, null, 582],
    [2, null, null, 655],
    [0, 167, 60, 679],
    [0, 169, null, 684],
    [2, null, null, 852],
    [0, 169, null, 873],
    [0, 167, 60, 885],
    [0, 55, null, 1151],
    [2, null, null, 1254]
  ],
  "offset": [3084042, 24, 1]
};

const RouteProcessingDemo = () => {
  const [processedData, setProcessedData] = useState<ProcessedRouteData | null>(null);
  const [nearestAlert, setNearestAlert] = useState<NearestAlertResult | null>(null);
  const [speedViolation, setSpeedViolation] = useState<SpeedViolationResult | null>(null);
  const [speedAlerts, setSpeedAlerts] = useState<SpeedAlertEvent[]>([]);
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

  const handleProcessRouteData = async () => {
    try {
      console.log('🗺️ Processing sample route data...');
      const result = await RnVietmapTrackingPlugin.processRouteData(SAMPLE_ROUTE_DATA);
      setProcessedData(result as ProcessedRouteData);

      Alert.alert(
        '✅ Success',
        `Route data processed!\nLinks: ${result.totalLinks}\nAlerts: ${result.totalAlerts}`
      );
    } catch (error) {
      console.error('Error processing route data:', error);
      Alert.alert('❌ Error', 'Failed to process route data');
    }
  };

  const handleGetCurrentRoute = async () => {
    try {
      const result = await RnVietmapTrackingPlugin.getCurrentRouteInfo();
      setProcessedData(result as ProcessedRouteData);
      Alert.alert('✅ Success', 'Current route info retrieved');
    } catch (error) {
      console.error('Error getting route info:', error);
      Alert.alert('❌ Error', 'No route data available');
    }
  };

  const handleFindNearestAlert = async () => {
    try {
      // Get current location first
      const location = await getCurrentLocation();
      console.log('📍 Current location:', location);

      // Find nearest alert
      const result = await RnVietmapTrackingPlugin.findNearestAlert(location.latitude, location.longitude);
      setNearestAlert(result as NearestAlertResult);

      Alert.alert(
        '✅ Success',
        `Found nearest alert!\nDistance: ${result.distanceToLink.toFixed(2)}m\nAlerts: ${result.alerts.length}`
      );
    } catch (error) {
      console.error('Error finding nearest alert:', error);
      Alert.alert('❌ Error', 'Failed to find nearest alert');
    }
  };

  const handleCheckSpeedViolation = async () => {
    try {
      // Simulate current speed (convert km/h to m/s)
      const speedKmh = 70; // 70 km/h
      const speedMs = speedKmh / 3.6; // Convert to m/s

      const result = await RnVietmapTrackingPlugin.checkSpeedViolation(speedMs);
      setSpeedViolation(result as SpeedViolationResult);

      const alertType = result.isViolation ? '🚨 VIOLATION' : '✅ OK';
      const message = result.isViolation
        ? `Speed: ${result.currentSpeed.toFixed(1)} km/h\nLimit: ${result.speedLimit} km/h\nExcess: ${result.excess.toFixed(1)} km/h`
        : `Speed: ${result.currentSpeed.toFixed(1)} km/h\nWithin limits`;

      Alert.alert(alertType, message);
    } catch (error) {
      console.error('Error checking speed violation:', error);
      Alert.alert('❌ Error', 'Failed to check speed violation');
    }
  };

  const handleClearData = () => {
    setProcessedData(null);
    setNearestAlert(null);
    setSpeedViolation(null);
    setSpeedAlerts([]);
  };

  return (
    <ScrollView style={styles.container}>
      <Text style={styles.title}>🗺️ Route Processing Demo</Text>

      {/* Action Buttons */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Actions</Text>

        <TouchableOpacity style={styles.button} onPress={handleProcessRouteData}>
          <Text style={styles.buttonText}>Process Sample Route Data</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.button} onPress={handleGetCurrentRoute}>
          <Text style={styles.buttonText}>Get Current Route Info</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.button} onPress={handleFindNearestAlert}>
          <Text style={styles.buttonText}>Find Nearest Alert</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.button} onPress={handleCheckSpeedViolation}>
          <Text style={styles.buttonText}>Check Speed Violation (70 km/h)</Text>
        </TouchableOpacity>

        <TouchableOpacity style={[styles.button, styles.clearButton]} onPress={handleClearData}>
          <Text style={styles.buttonText}>Clear All Data</Text>
        </TouchableOpacity>
      </View>

      {/* Processed Route Data */}
      {processedData && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>📊 Processed Route Data</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Total Links:</Text> {processedData.totalLinks}
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Total Alerts:</Text> {processedData.totalAlerts}
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>First Link ID:</Text> {processedData.links[0]?.id}
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Coordinates:</Text> {processedData.links[0]?.startLat.toFixed(6)}, {processedData.links[0]?.startLon.toFixed(6)}
            </Text>
          </View>
        </View>
      )}

      {/* Nearest Alert Info */}
      {nearestAlert && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>📍 Nearest Alert</Text>
          <View style={styles.infoBox}>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Link Index:</Text> {nearestAlert.nearestLinkIndex}
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Distance:</Text> {nearestAlert.distanceToLink.toFixed(2)}m
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Alerts Found:</Text> {nearestAlert.alerts.length}
            </Text>
            {nearestAlert.alerts.map((alert: RouteAlert, index: number) => (
              <Text key={index} style={styles.infoText}>
                Alert {index + 1}: Type {alert.type}, Distance {alert.distance}m
                {alert.speedLimit && `, Speed Limit: ${alert.speedLimit} km/h`}
              </Text>
            ))}
          </View>
        </View>
      )}

      {/* Speed Violation Info */}
      {speedViolation && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>
            {speedViolation.isViolation ? '🚨 Speed Violation' : '✅ Speed Check'}
          </Text>
          <View style={[styles.infoBox, speedViolation.isViolation && styles.violationBox]}>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Current Speed:</Text> {speedViolation.currentSpeed.toFixed(1)} km/h
            </Text>
            <Text style={styles.infoText}>
              <Text style={styles.bold}>Speed Limit:</Text> {speedViolation.speedLimit || 'N/A'}
            </Text>
            {speedViolation.isViolation && (
              <Text style={styles.infoText}>
                <Text style={styles.bold}>Excess:</Text> {speedViolation.excess.toFixed(1)} km/h
              </Text>
            )}
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
                <Text style={styles.bold}>Severity:</Text> {alert.severity}
              </Text>
              <Text style={styles.infoText}>
                <Text style={styles.bold}>Time:</Text> {new Date(alert.timestamp).toLocaleTimeString()}
              </Text>
            </View>
          ))}
        </View>
      )}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
    padding: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 20,
    color: '#333',
  },
  section: {
    backgroundColor: 'white',
    borderRadius: 8,
    padding: 16,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
    color: '#333',
  },
  button: {
    backgroundColor: '#007AFF',
    padding: 12,
    borderRadius: 8,
    marginBottom: 8,
  },
  clearButton: {
    backgroundColor: '#FF3B30',
  },
  buttonText: {
    color: 'white',
    textAlign: 'center',
    fontWeight: 'bold',
  },
  infoBox: {
    backgroundColor: '#f8f9fa',
    padding: 12,
    borderRadius: 6,
    borderLeftWidth: 4,
    borderLeftColor: '#007AFF',
  },
  violationBox: {
    borderLeftColor: '#FF3B30',
    backgroundColor: '#fff5f5',
  },
  alertBox: {
    borderLeftColor: '#FF9500',
    backgroundColor: '#fffbf0',
    marginBottom: 8,
  },
  infoText: {
    fontSize: 14,
    marginBottom: 4,
    color: '#333',
  },
  bold: {
    fontWeight: 'bold',
  },
});

export default RouteProcessingDemo;
