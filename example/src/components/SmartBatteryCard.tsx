import type { SmartBatteryPreset } from '@vietmap/rn_vietmap_tracking_plugin';
import { useTrackingStore } from '../store/trackingStore';
import { Card, Note, Segmented, Toggle } from './ui';

const PRESETS: { key: SmartBatteryPreset; label: string }[] = [
  { key: 'navigation', label: 'Navigation' },
  { key: 'general', label: 'General' },
  { key: 'batterySaver', label: 'Saver' },
];

export function SmartBatteryCard() {
  const enabled = useTrackingStore((s) => s.smartBatteryEnabled);
  const preset = useTrackingStore((s) => s.smartBatteryPreset);
  const setSmartBattery = useTrackingStore((s) => s.setSmartBattery);

  return (
    <Card title="Smart battery">
      <Toggle
        label="Enabled"
        value={enabled}
        onValueChange={(value) => setSmartBattery(value)}
        hint="Opt-in. Left on by default it would push its own cadence over whatever tracking just started with."
      />
      <Segmented
        options={PRESETS}
        value={preset}
        onChange={(value) => setSmartBattery(enabled, value)}
      />
      <Note>
        Navigation 5s · General 30s · Saver 5min. On iOS this also sets
        CoreLocation's activity type so the OS can pause updates when the
        vehicle is parked.
      </Note>
    </Card>
  );
}
