import { useTrackingStore } from '../store/trackingStore';
import { Card, Row } from './ui';

export function LocationCard() {
  const location = useTrackingStore((s) => s.currentLocation);
  if (!location) return null;

  return (
    <Card title="Current location">
      <Row label="Latitude" value={location.latitude.toFixed(6)} />
      <Row label="Longitude" value={location.longitude.toFixed(6)} />
      <Row label="Accuracy" value={`${location.accuracy.toFixed(1)} m`} />
      <Row label="Speed" value={`${location.speed.toFixed(1)} m/s`} />
      <Row label="Bearing" value={`${location.bearing.toFixed(1)}°`} />
      <Row label="Altitude" value={`${location.altitude.toFixed(1)} m`} />
      <Row label="Time" value={new Date(location.timestamp).toLocaleTimeString()} />
    </Card>
  );
}
