// @ts-ignore
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import React from 'react';
import { View, StyleSheet } from 'react-native';
import GPSTrackingDemo from './GPSTrackingDemo';

export default function App() {
  return (
    <View style={styles.container}>
      <GPSTrackingDemo />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
});
