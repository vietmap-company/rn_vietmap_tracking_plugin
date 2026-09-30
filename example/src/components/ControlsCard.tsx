import { useState } from 'react';
import { Alert } from 'react-native';
import { useTrackingStore } from '../store/trackingStore';
import { Button, Card, Row } from './ui';

export function ControlsCard() {
  const isTracking = useTrackingStore((s) => s.isTracking);
  const isInitialized = useTrackingStore((s) => s.isInitialized);
  const start = useTrackingStore((s) => s.start);
  const stop = useTrackingStore((s) => s.stop);
  const fetchCurrentLocation = useTrackingStore((s) => s.fetchCurrentLocation);
  const clearHistory = useTrackingStore((s) => s.clearHistory);

  const [busy, setBusy] = useState(false);

  const run = async (action: () => Promise<{ ok: boolean; message: string }>) => {
    setBusy(true);
    try {
      const result = await action();
      Alert.alert(result.ok ? 'Done' : 'Not started', result.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card title="Controls">
      <Row label="Tracking" value={isTracking ? 'active' : 'stopped'} />
      {isTracking ? (
        <Button title="Stop tracking" tone="danger" disabled={busy} onPress={() => run(stop)} />
      ) : (
        <Button
          title="Start tracking"
          disabled={busy || !isInitialized}
          onPress={() => run(start)}
        />
      )}
      <Button
        title="Get current location"
        tone="neutral"
        disabled={!isInitialized}
        onPress={async () => {
          try {
            const location = await fetchCurrentLocation();
            Alert.alert(
              'Current location',
              `${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)}\naccuracy ${location.accuracy}m`
            );
          } catch (error) {
            Alert.alert('Unavailable', String(error));
          }
        }}
      />
      <Button title="Clear local history" tone="neutral" onPress={clearHistory} />
    </Card>
  );
}
