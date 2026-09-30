import { useTrackingStore } from '../store/trackingStore';
import { Card, Field, Note } from './ui';

export function IdentityCard() {
  const userId = useTrackingStore((s) => s.userId);
  const vehicleId = useTrackingStore((s) => s.vehicleId);
  const setUserId = useTrackingStore((s) => s.setUserId);
  const setVehicleId = useTrackingStore((s) => s.setVehicleId);

  return (
    <Card title="Identity">
      <Field
        label="User ID"
        value={userId}
        onChangeText={setUserId}
        placeholder="required"
        hint="Written into every upload as userId. The SDK refuses to start tracking without it."
      />
      <Field
        label="Vehicle ID"
        value={vehicleId}
        onChangeText={setVehicleId}
        placeholder="optional"
      />
      <Note>
        Both travel inside the startTracking config, so there is no separate
        apply step — the plugin pushes them natively just before the start.
      </Note>
    </Card>
  );
}
