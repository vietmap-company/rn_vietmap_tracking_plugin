import { useTrackingStore } from '../store/trackingStore';
import { Button, Card, Row } from './ui';

function formatMs(value: number): string {
  if (value < 0) return 'no fix yet';
  if (value < 1000) return `${value} ms`;
  return `${Math.round(value / 1000)} s`;
}

export function TrackingStatusCard() {
  const health = useTrackingStore((s) => s.health);
  const refreshHealth = useTrackingStore((s) => s.refreshHealth);
  const isInitialized = useTrackingStore((s) => s.isInitialized);

  return (
    <Card title="Health">
      {health ? (
        <>
          <Row label="Tracking" value={health.isTracking ? 'active' : 'stopped'} />
          <Row label="Location permission" value={health.hasLocationPermission ? 'yes' : 'no'} />
          <Row label="Background permission" value={health.hasBackgroundPermission ? 'yes' : 'no'} />
          <Row label="Tracking duration" value={formatMs(health.trackingDuration)} />
          <Row label="Since last fix" value={formatMs(health.timeSinceLastUpdate)} />
        </>
      ) : (
        <Row label="Status" value="not read yet" />
      )}
      <Button
        title="Refresh health"
        tone="neutral"
        disabled={!isInitialized}
        onPress={refreshHealth}
      />
    </Card>
  );
}
