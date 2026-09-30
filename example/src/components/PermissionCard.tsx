import { useTrackingStore } from '../store/trackingStore';
import { Button, Card, Row } from './ui';

export function PermissionCard() {
  const hasPermissions = useTrackingStore((s) => s.hasPermissions);
  const requestPermissions = useTrackingStore((s) => s.requestPermissions);

  if (hasPermissions) {
    return (
      <Card title="Permissions">
        <Row label="Location" value="granted" />
      </Card>
    );
  }

  return (
    <Card title="Permissions">
      <Row label="Location" value="not granted" />
      <Button title="Request permissions" onPress={requestPermissions} />
    </Card>
  );
}
