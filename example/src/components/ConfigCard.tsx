import { TRACKING_PRESETS } from '@vietmap/rn_vietmap_tracking_plugin';
import { useTrackingStore, type TriggerMode } from '../store/trackingStore';
import { Button, Card, Dropdown, Field, Note, Toggle } from './ui';

type PresetKey = keyof typeof TRACKING_PRESETS;

/**
 * One row per preset, with the trigger it drives spelled out — the names alone
 * do not say whether a preset is timer-driven or distance-driven.
 */
const PRESET_OPTIONS = (Object.keys(TRACKING_PRESETS) as PresetKey[]).map((key) => {
  const preset = TRACKING_PRESETS[key];
  const detail =
    'intervalMs' in preset && preset.intervalMs != null
      ? `every ${preset.intervalMs / 1000}s`
      : 'distanceFilter' in preset && preset.distanceFilter != null
        ? `every ${preset.distanceFilter}m moved`
        : '';
  return { key, label: key.replace(/_/g, ' ').toLowerCase(), detail };
});

const MODE_OPTIONS: { key: TriggerMode; label: string; detail: string }[] = [
  {
    key: 'sdkDefault',
    label: 'SDK default',
    detail: 'Neither trigger sent — the SDK runs its own 10s timer, 25m floor',
  },
  { key: 'interval', label: 'Timer', detail: 'A fix every N ms, moving or not' },
  {
    key: 'distance',
    label: 'Distance',
    detail: 'A fix per N metres moved, none while stationary',
  },
];

export function ConfigCard() {
  const triggerMode = useTrackingStore((s) => s.triggerMode);
  const customInterval = useTrackingStore((s) => s.customInterval);
  const customDistance = useTrackingStore((s) => s.customDistance);
  const customBackgroundMode = useTrackingStore((s) => s.customBackgroundMode);
  const allowMockLocation = useTrackingStore((s) => s.allowMockLocation);
  const presetName = useTrackingStore((s) => s.presetName);
  const isTracking = useTrackingStore((s) => s.isTracking);

  const setTriggerMode = useTrackingStore((s) => s.setTriggerMode);
  const setCustomInterval = useTrackingStore((s) => s.setCustomInterval);
  const setCustomDistance = useTrackingStore((s) => s.setCustomDistance);
  const setCustomBackgroundMode = useTrackingStore((s) => s.setCustomBackgroundMode);
  const setAllowMockLocation = useTrackingStore((s) => s.setAllowMockLocation);
  const applyPreset = useTrackingStore((s) => s.applyPreset);
  const applyConfig = useTrackingStore((s) => s.applyConfig);

  return (
    <Card title="Configuration">
      <Dropdown
        label="Trigger"
        options={MODE_OPTIONS}
        value={triggerMode}
        onChange={setTriggerMode}
      />

      {triggerMode === 'interval' && (
        <Field
          label="Interval (ms)"
          value={customInterval}
          onChangeText={setCustomInterval}
          keyboardType="numeric"
          hint="The SDK raises anything under 5000."
        />
      )}
      {triggerMode === 'distance' && (
        <Field
          label="Distance filter (m)"
          value={customDistance}
          onChangeText={setCustomDistance}
          keyboardType="numeric"
          hint="The SDK raises anything under 25."
        />
      )}

      <Dropdown
        label="Preset"
        options={PRESET_OPTIONS}
        value={presetName as PresetKey | null}
        placeholder="None — using the trigger above"
        onChange={applyPreset}
      />

      <Toggle
        label="Background mode"
        value={customBackgroundMode}
        onValueChange={setCustomBackgroundMode}
        hint="Read once at start. Stop and start again to change it."
      />

      <Toggle
        label="Allow mock locations"
        value={allowMockLocation}
        onValueChange={setAllowMockLocation}
        hint="On by default so the demo works on a simulator, where every fix is simulated. Turn it off in production to enable fake GPS detection."
      />

      <Button
        title="Apply to running session"
        tone="neutral"
        disabled={!isTracking}
        onPress={applyConfig}
      />
      <Note>Applying mid-session changes the cadence only.</Note>
    </Card>
  );
}
