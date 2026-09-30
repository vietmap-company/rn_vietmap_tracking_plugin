import { View } from 'react-native';
import { useTrackingStore } from '../store/trackingStore';
import { Card, Note, Row } from './ui';

const VISIBLE = 10;

export function LocationHistoryCard() {
  const history = useTrackingStore((s) => s.locationHistory);
  if (history.length === 0) return null;

  // Newest first, and only the last few — the store keeps 50, which is more
  // than a phone screen can usefully show.
  const recent = history.slice(-VISIBLE).reverse();

  return (
    <Card title={`Received on device (${history.length})`}>
      <View>
        {recent.map((location, index) => (
          <Row
            key={`${location.timestamp}-${index}`}
            label={new Date(location.timestamp).toLocaleTimeString()}
            value={`${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)}`}
            mono
          />
        ))}
      </View>
      <Note>
        What the SDK delivered to this app, held in memory only — the last 50
        fixes, cleared when the app restarts.
        {history.length > VISIBLE ? ` Showing the ${VISIBLE} most recent.` : ''}
      </Note>
    </Card>
  );
}
