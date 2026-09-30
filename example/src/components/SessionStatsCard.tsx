import { useTrackingStore } from '../store/trackingStore';
import { Card, Row } from './ui';

export function SessionStatsCard() {
  const stats = useTrackingStore((s) => s.sessionStats);
  const totalDistanceMeters = useTrackingStore((s) => s.totalDistanceMeters);
  const count = useTrackingStore((s) => s.locationHistory.length);

  if (!stats) return null;

  return (
    <Card title="Session statistics">
      <Row label="Points" value={String(count)} />
      <Row label="Distance" value={`${(totalDistanceMeters() / 1000).toFixed(3)} km`} />
      <Row label="Duration" value={`${Math.round(stats.duration / 1000)} s`} />
      <Row label="Average speed" value={`${stats.averageSpeed.toFixed(1)} m/s`} />
    </Card>
  );
}
